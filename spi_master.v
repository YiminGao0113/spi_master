`timescale 1ns / 1ps

module spi_master #(parameter DATA_WIDTH = 32, parameter ADDRESS_WIDTH = 32)
(
    input                                      clock,
    input                                      reset_n,
    input [DATA_WIDTH-1:0]                     data,
    input [ADDRESS_WIDTH-1:0]                  address,
    input                                      enable,
    input                                      rd_we,
    input [15:0]                               divider,
    input                                      clock_phase,
    input                                      clock_polarity,
    input                                      MISO,

    output                                     SCK,
    output reg [DATA_WIDTH-1:0]                data_read,
    output reg                                 busy,
    output reg                                 SS,
    output reg                                 MOSI, 
    output reg                                 data_read_valid
);

parameter  IDLE = 3'b000;
parameter  SET_SS = 3'b001;
parameter  TRANSMIT_ADDRESS = 3'b011;
parameter  TRANSMIT_DATA = 3'b010;
parameter  READ_DATA = 3'b110;
parameter  STOP = 3'b111;

reg         [2:0]                               state;
reg         [2:0]                               state_nxt;
reg         [DATA_WIDTH-1:0]                    data_read_nxt;
reg                                             busy_nxt;
reg                                             SS_nxt;
reg                                             MOSI_nxt;
reg                                             data_read_valid_nxt;
reg         [7:0]                               bit_counter;
reg         [7:0]                               bit_counter_nxt;
reg                                             saved_rd_we;
reg                                             saved_rd_we_nxt;
reg                                             saved_CPHA;
reg                                             saved_CPHA_nxt;
reg                                             saved_CPOL;
reg                                             saved_CPOL_nxt;
reg         [ADDRESS_WIDTH-1:0]                 saved_address;
reg         [ADDRESS_WIDTH-1:0]                 saved_address_nxt;
reg         [DATA_WIDTH-1:0]                    saved_data;
reg         [DATA_WIDTH-1:0]                    saved_data_nxt;
reg         [DATA_WIDTH+ADDRESS_WIDTH:0]        MOSI_shift_register;
reg         [DATA_WIDTH+ADDRESS_WIDTH:0]        MOSI_shift_register_nxt;
reg         [DATA_WIDTH+ADDRESS_WIDTH:0]        MISO_shift_register;
reg         [DATA_WIDTH+ADDRESS_WIDTH:0]        MISO_shift_register_nxt;
wire                                            SCK;
wire                                            tick;
wire                                            sample;
reg                                             done;
reg                                             done_nxt;

// Instantiate the SPI clock generator
spi_clock_gen clock_gen (
    .clk            (clock),
    .reset_n        (reset_n),
    .cpha           (clock_phase),
    .cpol           (clock_polarity),
    .enable         (busy||busy_nxt),
    .divider        (divider),
    .spi_clk        (SCK),
    .tick           (tick),
    .sample         (sample),
    .stop           (done)
);

// Here we define the state transition logic
always @(*) begin
    // Initialization
    done_nxt                =    done;
    state_nxt               =    state;
    data_read_nxt           =    data_read;
    busy_nxt                =    busy;
    SS_nxt                  =    SS;
    MOSI_nxt                =    MOSI;
    data_read_valid_nxt     =    data_read_valid;
    bit_counter_nxt         =    bit_counter;
    saved_CPHA_nxt          =    saved_CPHA;
    saved_CPOL_nxt          =    saved_CPOL;
    saved_rd_we_nxt         =    saved_rd_we;
    saved_address_nxt       =    saved_address;
    saved_data_nxt          =    saved_data;
    MOSI_shift_register_nxt =    MOSI_shift_register;
    MISO_shift_register_nxt =    MISO_shift_register;
    
    case (state) 
        IDLE: begin
            done_nxt                    =    0;
            saved_CPHA_nxt              =    clock_phase;
            saved_CPOL_nxt              =    clock_polarity;
            saved_rd_we_nxt             =    rd_we;
            saved_address_nxt           =    address;
            saved_data_nxt              =    data;
            busy_nxt                    =    0;
            bit_counter_nxt             =    0; 
            MOSI_shift_register_nxt     =    0;
            MISO_shift_register_nxt     =    0;

            if (enable) begin
                busy_nxt                =   1;
                state_nxt               =   SET_SS;
            end
        end
        
        SET_SS: begin
            busy_nxt = 1;
            SS_nxt = 0;
            MOSI_shift_register_nxt = {saved_address, saved_rd_we, saved_data};
            state_nxt               = TRANSMIT_ADDRESS;
            // If CPHA == 0, means that MOSI has to start transmitting at the leading clock edge, no matter rising or falling
            if (saved_CPHA == 0) begin
                MOSI_nxt = saved_address[ADDRESS_WIDTH-1];
                MOSI_shift_register_nxt = {saved_address[ADDRESS_WIDTH-2:0], saved_rd_we, saved_data, 1'b0};
            end
        end

        TRANSMIT_ADDRESS: begin
            busy_nxt = 1;
            if (saved_CPHA == 1)
                bit_counter_nxt = 0; 
            else 
                bit_counter_nxt = 1;

            if (bit_counter == ADDRESS_WIDTH) begin
                bit_counter_nxt = 0;
                state_nxt = saved_rd_we ? READ_DATA : TRANSMIT_DATA;
                MOSI_nxt = MOSI_shift_register[ADDRESS_WIDTH+DATA_WIDTH];
                MOSI_shift_register_nxt = MOSI_shift_register << 1;
            end
            else begin
                bit_counter_nxt = bit_counter + 1;
                MOSI_nxt = MOSI_shift_register[ADDRESS_WIDTH+DATA_WIDTH];
                MOSI_shift_register_nxt = MOSI_shift_register << 1;
            end
        end

        READ_DATA: begin
            busy_nxt = 1;
            bit_counter_nxt = 0; 
            data_read_valid_nxt = 0;
            if (bit_counter == DATA_WIDTH) begin
                bit_counter_nxt = 0;
                state_nxt = STOP;
                data_read_valid_nxt = 1;
                data_read_nxt = MISO_shift_register;
            end
            // Here we leave one cycle for the slave to read the data
            else if(bit_counter == 0)
                bit_counter_nxt = bit_counter + 1;
            else begin
                bit_counter_nxt = bit_counter + 1;
                MISO_shift_register_nxt = {MISO_shift_register[ADDRESS_WIDTH+DATA_WIDTH:1], MISO};
            end
        end

        TRANSMIT_DATA: begin
            busy_nxt = 1;
            bit_counter_nxt = 0; 
            if (bit_counter == DATA_WIDTH-1) begin
                bit_counter_nxt = 0;
                state_nxt = STOP;
            end
            else begin
                bit_counter_nxt = bit_counter + 1;
                MOSI_nxt = MOSI_shift_register[ADDRESS_WIDTH+DATA_WIDTH];
                MOSI_shift_register_nxt = MOSI_shift_register << 1;
            end
        end

    STOP: begin
        done_nxt                = 1;
        SS_nxt                  = 1;       // Deselect the slave
        busy_nxt                = 0;       // Clear the busy flag
        data_read_valid_nxt     = 0;       // Clear the data read valid flag
        bit_counter_nxt         = 0;       // Reset the bit counter
        state_nxt               = IDLE;    // Transition back to the IDLE state
    end

    endcase
end

always @(posedge tick or negedge reset_n) begin
    if (!reset_n) begin
        state                   <= IDLE;
        busy                    <= 0;
        SS                      <= 1;
        MOSI                    <= 0;
        bit_counter             <= 0;
        saved_rd_we             <= 0;
        saved_CPHA              <= 0;
        saved_CPOL              <= 0;
        saved_address           <= 0;
        saved_data              <= 0;
        MOSI_shift_register     <= 0;
        MISO_shift_register     <= 0;
    end else begin
        state                   <= state_nxt;
        busy                    <= busy_nxt;
        SS                      <= SS_nxt;
        MOSI                    <= MOSI_nxt;
        bit_counter             <= bit_counter_nxt;
        saved_rd_we             <= saved_rd_we_nxt;
        saved_CPHA              <= saved_CPHA_nxt;
        saved_CPOL              <= saved_CPOL_nxt;
        saved_address           <= saved_address_nxt;
        saved_data              <= saved_data_nxt;
        MOSI_shift_register     <= MOSI_shift_register_nxt;
        MISO_shift_register     <= MISO_shift_register_nxt;
    end
end

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) done <= 0;
    else done <= done_nxt;
end

always @(posedge sample or negedge reset_n) begin
    if (!reset_n) begin
        data_read               <= 0;
        data_read_valid         <= 0;
    end else begin
        data_read               <= data_read_nxt;
        data_read_valid         <= data_read_valid_nxt;
    end
end

endmodule

module spi_clock_gen (
    input  wire        clk,         // System clock
    input  wire        reset_n,     // Active-low reset
    input  wire        cpha,        // Clock Phase
    input  wire        cpol,        // Clock Polarity
    input  wire        enable,      // Enable signal for SPI communication
    input  wire [15:0] divider,     // Divider value to control the SPI clock speed
    input              stop,

    output reg         spi_clk,     // SPI clock
    output             tick,        // Tick signal for updating MOSI
    output             sample       // Sample signal for sampling MISO
);

reg [15:0] divider_counter;         // Counter for clock division
reg enable_reg;
// SPI clock generation
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        spi_clk         <= cpol;
        // tick            <= (cpha == 0)? !cpol : cpol;
        // sample          <= (cpha == 0)?  cpol : !cpol;
        divider_counter <= 0;
    end else if (enable_reg) begin
        // if (divider_counter == 1) begin
        //     tick            <= ~tick;
        //     sample          <= ~sample;
        //     divider_counter <= divider_counter + 1;
        // end
        // else 
        if (divider_counter == divider) begin
            divider_counter <= 0;
            spi_clk         <= ~spi_clk; // Toggle SPI clock
        end else begin
            divider_counter <= divider_counter + 1;
        end
    end else begin
        spi_clk         <= cpol;
        // tick            <= (cpha == 0)? !cpol : cpol;
        // sample          <= (cpha == 0)?  cpol : !cpol;
        divider_counter <= 0;
    end
end

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) enable_reg <= 0;
    else begin
        if (enable) enable_reg <= 1;
        else if (stop) enable_reg <= 0;
    end

end


// Determine when to update MOSI and sample MISO based on CPHA and current state of spi_clk
assign tick   = (cpha == 0) ? ~spi_clk : spi_clk;
assign sample = (cpha == 0) ? spi_clk : ~spi_clk;

endmodule
