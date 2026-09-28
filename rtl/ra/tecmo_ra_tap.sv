// SPDX-License-Identifier: GPL-3.0-or-later
//
// RetroAchievements tap for the Tecmo MiSTer core (Rygar only: the other
// games of the core have no RetroAchievements set and a different map).
//
// Turns the memory writes of the main and sound Z80s into writes of the RA
// shadow (rtl/ra/ra_shadow.v), laid out as FinalBurn Neo's d_tecmo.cpp
// "All Ram" block for rygar (MemIndex order, byte for byte):
//
//   0x0000 DrvZ80RAM0   0x1000  main C000-CFFF
//   0x1000 DrvZ80RAM1   0x0800  sound 4000-47FF
//   0x1800 DrvPalRAM    0x0800  main E800-EFFF
//   0x2000 DrvTextRAM   0x0800  main D000-D7FF
//   0x2800 DrvBackRAM   0x0400  main DC00-DFFF
//   0x2C00 DrvForeRAM   0x0400  main D800-DBFF
//   0x3000 DrvSprRAM    0x0800  main E000-E7FF
//   0x3800 DrvBgScroll  UINT16[2]: F803 low byte, F804 high byte, F805 -> [1]
//   0x3804 DrvFgScroll  UINT16[2]: F800 low byte, F801 high byte, F802 -> [1]
//   (0x3808 DrvPalette, 0x1000 bytes of host colours, is not mirrored)
//
// Writes are level strobes held for a whole Z80 write cycle, so when both
// CPUs write at once the port alternates between them every clock.

module tecmo_ra_tap (
    input             clk,
    input             enable,       // game is Rygar
    input             m_wr,
    input      [15:0] m_a,
    input       [7:0] m_d,
    input             s_wr,
    input      [15:0] s_a,
    input       [7:0] s_d,
    output reg        ra_wr,
    output reg [12:0] ra_word,
    output reg [15:0] ra_din,
    output reg  [1:0] ra_be
);

reg  [13:0] m_off;
reg         m_hit, m_word;   // m_word: 16-bit write {0x00, data} (scroll [1])
always @(*) begin
    m_hit  = 1'b1;
    m_word = 1'b0;
    m_off  = 14'd0;
    casez (m_a)
        16'b1100_????_????_????: m_off = 14'h0000 + {2'd0, m_a[11:0]};   // C000-CFFF
        16'b1110_1???_????_????: m_off = 14'h1800 + {3'd0, m_a[10:0]};   // E800-EFFF
        16'b1101_0???_????_????: m_off = 14'h2000 + {3'd0, m_a[10:0]};   // D000-D7FF
        16'b1101_11??_????_????: m_off = 14'h2800 + {4'd0, m_a[9:0]};    // DC00-DFFF
        16'b1101_10??_????_????: m_off = 14'h2C00 + {4'd0, m_a[9:0]};    // D800-DBFF
        16'b1110_0???_????_????: m_off = 14'h3000 + {3'd0, m_a[10:0]};   // E000-E7FF
        16'hF800: m_off = 14'h3804;
        16'hF801: m_off = 14'h3805;
        16'hF802: begin m_off = 14'h3806; m_word = 1'b1; end
        16'hF803: m_off = 14'h3800;
        16'hF804: m_off = 14'h3801;
        16'hF805: begin m_off = 14'h3802; m_word = 1'b1; end
        default: m_hit = 1'b0;
    endcase
end

wire s_hit = s_a[15:11] == 5'b0100_0;                                 // 4000-47FF
wire [13:0] s_off = 14'h1000 + {3'd0, s_a[10:0]};

wire m_go = enable && m_wr && m_hit;
wire s_go = enable && s_wr && s_hit;
reg  turn = 1'b0;   // 1: sound goes first when both write

always @(posedge clk) begin
    ra_wr <= 1'b0;
    if (s_go && (turn || !m_go)) begin
        turn    <= 1'b0;
        ra_wr   <= 1'b1;
        ra_word <= s_off[13:1];
        ra_din  <= {s_d, s_d};
        ra_be   <= s_off[0] ? 2'b10 : 2'b01;
    end else if (m_go) begin
        turn    <= 1'b1;
        ra_wr   <= 1'b1;
        ra_word <= m_off[13:1];
        ra_din  <= m_word ? {8'h00, m_d} : {m_d, m_d};
        ra_be   <= m_word ? 2'b11 : m_off[0] ? 2'b10 : 2'b01;
    end
end

endmodule
