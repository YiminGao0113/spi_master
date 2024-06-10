`timescale 1ns / 1ps

module spi_master #(parameter DATA_WIDTH = 32, parameter ADDRESS_WIDTH = 32, parameter CYCLE_TO_WRITE = 3)
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

// State encoding
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
reg                                             serial_clk;
reg                                             tick;
reg [15:0]                                      counter;

assign SCK = serial_clk;


// Clock divider to generate serial clock and tick signal
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        serial_clk <= clock_polarity;
        counter    <= 0;
        tick       <= clock_phase;
    end else if (!SS) begin
        busy <= 1;
        if (counter != divider-1) begin
            counter <= counter + 1;
            // tick <= !clock_phase;
        end else begin
            counter <= 0;
            serial_clk <= !serial_clk;
            tick <= !tick; // Generate tick on serial_clk toggle
        end
    end
    else begin
        serial_clk <= clock_polarity;
        counter    <= 0;
        tick       <= clock_phase;
    end
end


// State transition logic
always @(*) begin
    // Initialization
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
            saved_CPHA_nxt              =    clock_phase;
            saved_CPOL_nxt              =    clock_polarity;
            saved_rd_we_nxt             =    rd_we;
            saved_address_nxt           =    address;
            saved_data_nxt              =    data;
            bit_counter_nxt             =    0; 
            MOSI_shift_register_nxt     =    0;
            MISO_shift_register_nxt     =    0;
            MOSI_nxt                    =    1'bZ;

            if (enable) begin
                busy_nxt                =   1;
                state_nxt               =   SET_SS;
            end
        end
        
        SET_SS: begin
            busy_nxt = 1;
            MOSI_shift_register_nxt = {saved_address, saved_rd_we, saved_data};
            SS_nxt = 0;
            state_nxt               = TRANSMIT_ADDRESS;
            // If CPHA == 0, means that MOSI has to start transmitting at the leading clock edge, no matter rising or falling
            if (saved_CPHA == 0) begin
                MOSI_nxt = saved_address[ADDRESS_WIDTH-1];
                MOSI_shift_register_nxt = {saved_address[ADDRESS_WIDTH-2:0], saved_rd_we, saved_data, 1'b0};
            end
        end

        TRANSMIT_ADDRESS: begin
            busy_nxt = 1;
            if (tick) begin
                MOSI_nxt = MOSI_shift_register[DATA_WIDTH+ADDRESS_WIDTH];
                MOSI_shift_register_nxt = MOSI_shift_register << 1;
                if (bit_counter == ADDRESS_WIDTH) begin
                    bit_counter_nxt = 0;
                    state_nxt = saved_rd_we ? READ_DATA : TRANSMIT_DATA;
                end else begin
                    bit_counter_nxt = bit_counter + 1;
                end
            end
        end

        READ_DATA: begin
            busy_nxt = 1;
            if (tick) begin
                if (bit_counter == DATA_WIDTH) begin
                    bit_counter_nxt = 0;
                    state_nxt = STOP;
                    data_read_valid_nxt = 1;
                    data_read_nxt = MISO_shift_register[DATA_WIDTH-1:0];
                end else begin
                    bit_counter_nxt = bit_counter + 1;
                    MISO_shift_register_nxt = {MISO_shift_register[DATA_WIDTH+ADDRESS_WIDTH:1], MISO};
                end
            end
        end

        TRANSMIT_DATA: begin
            busy_nxt = 1;
            if (tick) begin
                if (bit_counter == DATA_WIDTH-1) begin
                    bit_counter_nxt = 0;
                    state_nxt = STOP;
                end else begin
                    bit_counter_nxt = bit_counter + 1;
                    MOSI_nxt = MOSI_shift_register[DATA_WIDTH+ADDRESS_WIDTH];
                    MOSI_shift_register_nxt = MOSI_shift_register << 1;
                end
            end
        end

        STOP: begin
            // SS_nxt                  = 1;       // Deselect the slave
            // busy_nxt                = 0;       // Clear the busy flag
            // data_read_valid_nxt     = 0;       // Clear the data read valid flag
            // bit_counter_nxt         = 0;       // Reset the bit counter
            if (tick) begin
                MOSI_nxt = 1'bZ;
                if (bit_counter == CYCLE_TO_WRITE-1) begin
                    bit_counter_nxt = 0;
                    state_nxt = IDLE;
                    SS_nxt                  = 1;       // Deselect the slave
                    busy_nxt                = 0;       // Clear the busy flag
                    data_read_valid_nxt     = 0;       // Clear the data read valid flag
                end else begin
                    bit_counter_nxt = bit_counter + 1;
                end

            end
        end

        default: begin
            state_nxt = IDLE;
        end
    endcase
end

// State and register updates
always @(posedge tick or negedge reset_n) begin
    if (!reset_n) begin
        // busy                    <= 0;
        // MOSI                    <= 0;
        bit_counter             <= 0;
        saved_rd_we             <= 0;
        saved_CPHA              <= 0;
        saved_CPOL              <= 0;
        MISO_shift_register     <= 0;
        data_read               <= 0;
        data_read_valid         <= 0;
        MOSI_shift_register     <= 0;
    end else begin
        if (state != IDLE && state != STOP) begin
            state <= state_nxt;
            MOSI                    <= MOSI_nxt;
        end
        // busy                    <= busy_nxt;
        bit_counter             <= bit_counter_nxt;
        saved_rd_we             <= saved_rd_we_nxt;
        saved_CPHA              <= saved_CPHA_nxt;
        saved_CPOL              <= saved_CPOL_nxt;
        MISO_shift_register     <= MISO_shift_register_nxt;
        data_read               <= data_read_nxt;
        data_read_valid         <= data_read_valid_nxt;
        MOSI_shift_register     <= MOSI_shift_register_nxt;
    end
end

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        state                   <= IDLE;
        busy <= 0;
        SS   <= 1;
        MOSI <= 1'bZ;
        saved_address           <= 0;
        saved_data              <= 0;
    end
    else begin
        if (state == IDLE||state == STOP) begin
            state <= state_nxt;
            MOSI  <= MOSI_nxt;
        end
        busy <= busy_nxt;
        SS   <= SS_nxt;
        saved_address           <= saved_address_nxt;
        saved_data              <= saved_data_nxt;
    end
end
endmodule
