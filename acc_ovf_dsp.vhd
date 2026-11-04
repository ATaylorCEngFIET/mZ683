-------------------------------------------------------------------------------
-- acc_ovf_dsp.vhd
--
-- MicroZed Chronicles: Flags for Free
--
-- A 48-bit accumulator in one DSP48E2 (P = P + A:B) with overflow and
-- underflow detection from the pattern detector, and an optional saturating
-- output.
--
-- The valid range is -2**N .. 2**N - 1. PATTERN is all zeros and MASK has
-- ones in its N least significant bits, so:
--
--   PATTERNDETECT  = 1  when P[47:N] are all zero  (P in 0 .. 2**N - 1)
--   PATTERNBDETECT = 1  when P[47:N] are all one   (P in -2**N .. -1)
--   in_range       = PATTERNDETECT or PATTERNBDETECT
--
-- OVERFLOW and UNDERFLOW are single-cycle pulses. OVERFLOW is high in the
-- first cycle that P leaves the range in the positive direction and UNDERFLOW
-- in the first cycle it leaves in the negative direction. They are relative
-- to the previous value: a value that stays out of range raises no further
-- pulses, and a return into range raises nothing at all.
--
-- The slice never clamps P itself. acc_sat is P while it is in range and the
-- nearest limit when it is not. The two limits fall out of the mask:
--   positive limit  2**N - 1  =      MASK  (ones in the low N bits)
--   negative limit -2**N      =  not MASK  (ones in the high 48 - N bits)
--
-- With SATURATE = true the accumulator becomes a true saturating accumulator:
-- when P is out of range the Z multiplexer is switched from P to the C input,
-- which carries the clamped value, so the next accumulation starts from the
-- limit rather than from the out-of-range value. This puts a fabric path from
-- the pattern detector outputs through the clamp multiplexer to OPMODE and C,
-- so OPMODEREG and CREG are zero and the path shows up in report_timing.
-- With SATURATE = false P carries on unclamped (it has plenty of headroom in
-- 48 bits) and only acc_sat is clamped.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity acc_ovf_dsp is
  generic (
    N        : positive range 1 to 46 := 8;   -- valid range -2**N .. 2**N - 1
    SATURATE : boolean := false               -- feed the clamp back into P
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;                     -- synchronous, active high
    en        : in  std_logic;                     -- accumulate enable (CEP)
    din       : in  std_logic_vector(47 downto 0); -- signed addend
    acc       : out std_logic_vector(47 downto 0); -- P, unclamped
    acc_sat   : out std_logic_vector(47 downto 0); -- P clamped to the range
    in_range  : out std_logic;
    overflow  : out std_logic;                     -- one-cycle pulse
    underflow : out std_logic                      -- one-cycle pulse
  );
end entity acc_ovf_dsp;

architecture rtl of acc_ovf_dsp is

  function mask_for(nbits : positive) return std_logic_vector is
    variable m : std_logic_vector(47 downto 0) := (others => '0');
  begin
    m(nbits - 1 downto 0) := (others => '1');
    return m;
  end function mask_for;

  constant C_MASK    : std_logic_vector(47 downto 0) := mask_for(N);
  constant C_POS_LIM : std_logic_vector(47 downto 0) := C_MASK;        --  2**N - 1
  constant C_NEG_LIM : std_logic_vector(47 downto 0) := not C_MASK;    -- -2**N
  constant C_ZERO48  : std_logic_vector(47 downto 0) := (others => '0');

  signal p        : std_logic_vector(47 downto 0);
  signal p_clamp  : std_logic_vector(47 downto 0);
  signal pd, pbd  : std_logic;
  signal p_fresh  : std_logic := '1';   -- P is zero from reset, see below
  signal inr      : std_logic;
  signal opmode_z : std_logic_vector(2 downto 0);
  signal c_in     : std_logic_vector(47 downto 0);

begin

  -- The pattern detector outputs are registered and come out of reset (RSTP
  -- or the global GSR) low, even though P is zero and zero is inside the
  -- range. Without this flag the clamp would read "out of range" during reset
  -- and for the first cycle after it, acc_sat would show the positive limit,
  -- and in saturating mode the first accumulation would start from 2**N - 1
  -- instead of 0. p_fresh is high while P holds its reset value and has not
  -- yet been loaded; its initial value covers power-up without a reset.
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p_fresh <= '1';
      elsif en = '1' then
        p_fresh <= '0';
      end if;
    end if;
  end process;

  -- the clamp: a 48-bit two-way multiplexer and a 48-bit constant select
  inr     <= pd or pbd or p_fresh;
  p_clamp <= p         when inr = '1' else
             C_NEG_LIM when p(47) = '1' else
             C_POS_LIM;

  -- Z selects P (010) normally. In saturating mode it selects C (011) while P
  -- is out of range, and C carries the clamped value.
  g_sat : if SATURATE generate
    opmode_z <= "010" when inr = '1' else "011";
    c_in     <= p_clamp;
  end generate g_sat;

  g_nosat : if not SATURATE generate
    opmode_z <= "010";
    c_in     <= C_ZERO48;
  end generate g_nosat;

  acc       <= p;
  acc_sat   <= p_clamp;
  in_range  <= inr;

  -- OPMODE[8:7] W = 00, [6:4] Z = P or C, [3:2] Y = 00, [1:0] X = 11 (A:B)
  -- ALUMODE 0000 : Z + W + X + Y + CIN,  CARRYIN = 0

  acc_dsp : DSP48E2
    generic map (
      USE_MULT           => "NONE",
      USE_PATTERN_DETECT => "PATDET",
      PATTERN            => C_ZERO48,
      MASK               => C_MASK,             -- ones in the low N bits
      SEL_PATTERN        => "PATTERN",
      SEL_MASK           => "MASK",
      AUTORESET_PATDET   => "NO_RESET",
      AREG => 0, BREG => 0, ACASCREG => 0, BCASCREG => 0,
      ADREG => 0, DREG => 0, CREG => 0, MREG => 0,
      OPMODEREG => 0, ALUMODEREG => 0, CARRYINREG => 0,
      CARRYINSELREG => 0, INMODEREG => 0,
      PREG => 1)
    port map (
      ACOUT          => open,
      BCOUT          => open,
      CARRYCASCOUT   => open,
      CARRYOUT       => open,
      MULTSIGNOUT    => open,
      OVERFLOW       => overflow,
      P              => p,
      PATTERNBDETECT => pbd,
      PATTERNDETECT  => pd,
      PCOUT          => open,
      UNDERFLOW      => underflow,
      XOROUT         => open,
      ACIN           => (others => '0'),
      BCIN           => (others => '0'),
      CARRYCASCIN    => '0',
      MULTSIGNIN     => '0',
      PCIN           => (others => '0'),
      ALUMODE        => "0000",
      CARRYINSEL     => "000",
      CLK            => clk,
      INMODE         => "00000",
      OPMODE         => "00" & opmode_z & "00" & "11",
      A              => din(47 downto 18),      -- A:B is the 48-bit addend
      B              => din(17 downto 0),
      C              => c_in,
      CARRYIN        => '0',
      D              => (others => '0'),
      CEA1 => '0', CEA2 => '0', CEAD => '0', CEALUMODE => '0',
      CEB1 => '0', CEB2 => '0', CEC => '0', CECARRYIN => '0',
      CECTRL => '0', CED => '0', CEINMODE => '0', CEM => '0',
      CEP            => en,
      RSTA => '0', RSTALLCARRYIN => '0', RSTALUMODE => '0', RSTB => '0',
      RSTC => '0', RSTCTRL => '0', RSTD => '0', RSTINMODE => '0', RSTM => '0',
      RSTP           => rst);

end architecture rtl;
