`timescale 1ns / 1ps

module tb;

reg clock;
reg reset_n;
reg [31:0] data;
reg [31:0] address;
reg enable;
reg rd_we;
reg [15:0] divider;
reg clock_phase;
reg clock_polarity;
wire SCK;
wire [31:0] data_read;
wire [31:0] data_read_slave;
wire busy;
wire SS;
wire MOSI;
wire data_read_valid;
wire MISO;

// Clock generation
always begin
    #5 clock = ~clock;
end

// Instantiate the SPI master
spi_master #(.DATA_WIDTH(32), .ADDRESS_WIDTH(32)) spi_master_inst (
    .clock(clock),
    .reset_n(reset_n),
    .data(data),
    .address(address),
    .enable(enable),
    .rd_we(rd_we),
    .divider(divider),
    .clock_phase(clock_phase),
    .clock_polarity(clock_polarity),
    .MISO(MISO),
    .SCK(SCK),
    .data_read(data_read),
    .busy(busy),
    .SS(SS),
    .MOSI(MOSI),
    .data_read_valid(data_read_valid)
);

// Instantiate the SPI slave
spi_slave #(.DATA_WIDTH(32), .ADDRESS_WIDTH(32)) spi_slave_inst (
    .SCK(SCK),
    .CPHA(clock_phase),
    .SS(SS),
    .MOSI(MOSI),
    .MISO(MISO),
    .reset_n(reset_n),
    .data_read(data_read_slave),
    .data_write(data)
    // .address(address),
    // .write_enable(rd_we)
);

initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);

    clock = 0;
    reset_n = 0;
    data = 32'hA5A5A5A5;
    address = 32'h80000010;
    enable = 0;
    rd_we = 0;
    divider = 2;
    clock_phase = 0;
    clock_polarity = 0;

    #10 reset_n = 1;
    #40 enable = 1;
    #10 enable = 0;
    #4000 

    // Finish simulation
    #100 $finish;
end

endmodule
