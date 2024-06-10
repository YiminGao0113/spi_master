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
wire slave_clock;
reg initialization;

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
    .SCK(slave_clock),
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

assign slave_clock = initialization? clock : SCK;

initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    // Initialize signals

    clock = 0;
    reset_n = 0;
    initialization = 1;

    data = 32'hA5A5A5A5;
    address = 32'h00000010;
    enable = 0;
    rd_we = 0;
    divider = 2;
    clock_phase = 0;
    clock_polarity = 0;

    // Reset the system
    #10 reset_n = 1;
    initialization = 0;

    // Perform write operation
    #100 enable = 1;
    rd_we = 1;

    #10 enable = 0;
    rd_we = 0;

    // Wait for the operation to complete
    #4000 

    // Perform read operation
    #10 enable = 1;
    rd_we = 0;
    #10 enable = 0;

    // Wait for the operation to complete
    #2000 enable = 0;

    // Finish simulation
    #100 $finish;
end

endmodule
