`timescale 1ns / 1ps

module spi_slave #(
    parameter DATA_WIDTH = 32,
    parameter ADDRESS_WIDTH = 32,
    parameter CYCLE_TO_WRITE = 2
)(
    input                      SCK,            // SPI clock from master
    input                      CPHA,
    input                      SS,             // Slave select from master
    input                      MOSI,           // Master out, slave in
    output reg                 MISO,           // Master in, slave out
    input                      reset_n,        // Active-low reset
    output reg [DATA_WIDTH-1:0] data_read,     // Data read from slave
    input [DATA_WIDTH-1:0]     data_write      // Data to write to slave
    // input [ADDRESS_WIDTH-1:0]  address,        // Address to access
    // input                      write_enable    // Write enable signal
);

reg [DATA_WIDTH-1:0] reg_file [0:ADDRESS_WIDTH-1];  // Register file

reg [7:0] bit_counter;    // Counter to track bit position
reg [ADDRESS_WIDTH+DATA_WIDTH-1:0] shift_reg_in;    // Shift register for incoming data
reg [DATA_WIDTH-1:0] shift_reg_out;   // Shift register for outgoing data
wire tick, sample;
reg write_enable;

// State machine states
parameter IDLE = 3'b000;
parameter RECEIVE_ADDRESS = 3'b001;
parameter FETCH_DATA = 3'b011;
parameter SEND_DATA = 3'b010;
parameter RECEIVE_DATA = 3'b110;
parameter WRITE_DATA = 3'b111;

reg [2:0] state, state_nxt;
reg [7:0] bit_counter_nxt;
reg [ADDRESS_WIDTH+DATA_WIDTH-1:0] shift_reg_in_nxt;
reg [DATA_WIDTH-1:0] shift_reg_out_nxt;
reg [DATA_WIDTH-1:0] data_read_nxt;
reg [ADDRESS_WIDTH-1:0] received_address;
reg [ADDRESS_WIDTH-1:0] received_address_nxt;
reg [DATA_WIDTH-1:0] received_data;
reg [DATA_WIDTH-1:0] data_test;

reg [DATA_WIDTH-1:0] received_data_nxt;
reg MISO_nxt;

assign tick   = (CPHA == 0) ? SCK : !SCK;
assign sample = (CPHA == 0) ? !SCK : SCK;

// Next state and signal logic
always @(*) begin
    // Initialization
    state_nxt           = state;
    bit_counter_nxt     = bit_counter;
    shift_reg_in_nxt    = shift_reg_in;
    shift_reg_out_nxt   = shift_reg_out;
    data_read_nxt       = data_read;
    received_address_nxt= received_address;
    received_data_nxt   = received_data;
    MISO_nxt            = MISO;
    write_enable        = 0;
    
    case (state) 
        IDLE: begin
            received_address_nxt = 0;
            received_data_nxt    = 0;
            if (!SS) begin
                bit_counter_nxt     = 0;
                state_nxt           = RECEIVE_ADDRESS;
            end
        end
        
        RECEIVE_ADDRESS: begin
            if (bit_counter < ADDRESS_WIDTH) begin
                shift_reg_in_nxt    = {shift_reg_in[ADDRESS_WIDTH+DATA_WIDTH-2:0], MOSI};
                bit_counter_nxt     = bit_counter + 1;
            end else begin
                received_address_nxt= shift_reg_in[ADDRESS_WIDTH-1:0];
                bit_counter_nxt     = 0;
                state_nxt           = MOSI ? FETCH_DATA : RECEIVE_DATA;
            end
        end

        FETCH_DATA: begin
            data_read_nxt          = reg_file[received_address];
            shift_reg_out_nxt      = reg_file[received_address];
            state_nxt              = SEND_DATA;
        end

        SEND_DATA: begin
            if (bit_counter < DATA_WIDTH) begin
                MISO_nxt            = shift_reg_out[DATA_WIDTH-1];
                shift_reg_out_nxt   = shift_reg_out << 1;
                bit_counter_nxt     = bit_counter + 1;
            end else begin
                state_nxt           = IDLE;
                MISO_nxt            = 1'bZ;
            end
        end

        RECEIVE_DATA: begin
            if (bit_counter < DATA_WIDTH) begin
                shift_reg_in_nxt    = {shift_reg_in[ADDRESS_WIDTH+DATA_WIDTH-2:0], MOSI};
                bit_counter_nxt     = bit_counter + 1;
            end else begin
                received_data_nxt   = shift_reg_in[DATA_WIDTH-1:0];
                bit_counter_nxt     = 0;
                state_nxt           = WRITE_DATA;
            end
        end

        WRITE_DATA: begin
            if (bit_counter == CYCLE_TO_WRITE-1) begin
                bit_counter_nxt            = 0;
                state_nxt                  = IDLE;
            end
            else begin
                bit_counter_nxt        = bit_counter + 1;
                write_enable               = 1;
            end
        end

    endcase
end

// Register update on tick
always @(posedge tick or negedge reset_n) begin
    if (!reset_n) begin
        state               <= IDLE;
        bit_counter         <= 0;
        shift_reg_out       <= 0;
        received_address    <= 0;
        MISO                <= 0;
    end else begin
        MISO                <= MISO_nxt;
        state               <= state_nxt;
        bit_counter         <= bit_counter_nxt;
        shift_reg_out       <= shift_reg_out_nxt;
        received_address    <= received_address_nxt;
    end
end

// Register update on sample
always @(posedge sample or negedge reset_n) begin
    if (!reset_n) begin
        shift_reg_in        <= 0;
        received_data       <= 0;
    end else begin
        shift_reg_in        <= shift_reg_in_nxt;
        received_data       <= received_data_nxt;
    end
end

integer i;
always @(posedge SCK or negedge reset_n) begin
    if (!reset_n) begin
        // Optional: Initialize register file with zeros or specific values
        for (i = 0; i < (1<<ADDRESS_WIDTH); i = i + 1) begin
            reg_file[i] <= 0;
        end
    end else if (write_enable) begin
        reg_file[received_address] <= received_data;
    end
end

always @(posedge SCK or negedge reset_n) begin
    if (!reset_n) begin
        data_read <= 0;
    end else begin
        data_test <= reg_file[received_address];
    end
end

endmodule
