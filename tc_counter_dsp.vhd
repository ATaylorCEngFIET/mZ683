-------------------------------------------------------------------------------
-- tc_counter_dsp.vhd
--
-- MicroZed Chronicles: Flags for Free
--
-- A 48-bit counter with a terminal count flag, implemented entirely inside one
-- DSP48E2. The count is P = P + CARRYIN with CARRYIN tied high, the terminal
-- count compare is the pattern detector (PATTERN = TC, MASK = all zeros so
-- every bit is compared) and AUTORESET_PATDET = RESET_MATCH returns P to zero
-- on the cycle after the match, so the counter runs 0 .. TC with a period of
-- TC + 1 clocks. No fabric LUTs are used for the count or the compare.
--
-- tc_flag is the registered PATTERNDETECT output. It is high in the same cycle
-- that count shows the terminal value.
--
-- AUTORESET_PRIORITY is set to CEP so that the automatic reset only happens
-- when the counter is enabled. With RESET priority the slice would reset P on
-- the cycle after the match even if en were low.
--
-- Attribute and port names follow the UltraScale Architecture Libraries Guide
-- (UG974) DSP48E2 instantiation template. Only the attributes that differ from
-- the template defaults are given in the generic map.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity tc_counter_dsp is
  generic (
    TC : natural := 9      -- terminal count, counter runs 0 .. TC
                           -- (for values above 2**31 - 1 change the generic
                           -- to a 48-bit std_logic_vector)
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;                      -- synchronous, active high
    en      : in  std_logic;                      -- count enable (CEP)
    count   : out std_logic_vector(47 downto 0);
    tc_flag : out std_logic                       -- high when count = TC
  );
end entity tc_counter_dsp;

architecture rtl of tc_counter_dsp is

  constant C_PATTERN : std_logic_vector(47 downto 0) :=
    std_logic_vector(to_unsigned(TC, 48));

  constant C_ZERO48 : std_logic_vector(47 downto 0) := (others => '0');

begin

  -- OPMODE[8:7] W = 00 (zero)
  -- OPMODE[6:4] Z = 010 (P, requires PREG = 1)
  -- OPMODE[3:2] Y = 00 (zero)
  -- OPMODE[1:0] X = 00 (zero)
  -- ALUMODE 0000 : Z + W + X + Y + CIN  ->  P + 1 each enabled clock
  -- CARRYINSEL 000 : CIN comes from the CARRYIN pin

  cnt_dsp : DSP48E2
    generic map (
      -- no multiplier, pattern detector on
      USE_MULT           => "NONE",
      USE_PATTERN_DETECT => "PATDET",
      -- the compare
      PATTERN            => C_PATTERN,        -- terminal count
      MASK               => C_ZERO48,         -- compare all 48 bits
      SEL_PATTERN        => "PATTERN",
      SEL_MASK           => "MASK",
      -- the automatic reset of P on the cycle after the match
      AUTORESET_PATDET   => "RESET_MATCH",
      AUTORESET_PRIORITY => "CEP",
      -- pipeline registers: only the P register is used
      AREG => 0, BREG => 0, ACASCREG => 0, BCASCREG => 0,
      ADREG => 0, DREG => 0, CREG => 0, MREG => 0,
      OPMODEREG => 0, ALUMODEREG => 0, CARRYINREG => 0,
      CARRYINSELREG => 0, INMODEREG => 0,
      PREG => 1)
    port map (
      -- outputs
      ACOUT          => open,
      BCOUT          => open,
      CARRYCASCOUT   => open,
      CARRYOUT       => open,
      MULTSIGNOUT    => open,
      OVERFLOW       => open,
      P              => count,
      PATTERNBDETECT => open,
      PATTERNDETECT  => tc_flag,
      PCOUT          => open,
      UNDERFLOW      => open,
      XOROUT         => open,
      -- cascade inputs, unused
      ACIN           => (others => '0'),
      BCIN           => (others => '0'),
      CARRYCASCIN    => '0',
      MULTSIGNIN     => '0',
      PCIN           => (others => '0'),
      -- control
      ALUMODE        => "0000",
      CARRYINSEL     => "000",
      CLK            => clk,
      INMODE         => "00000",
      OPMODE         => "000100000",
      -- data
      A              => (others => '0'),
      B              => (others => '0'),
      C              => (others => '0'),
      CARRYIN        => '1',                  -- count by one
      D              => (others => '0'),
      -- clock enables
      CEA1 => '0', CEA2 => '0', CEAD => '0', CEALUMODE => '0',
      CEB1 => '0', CEB2 => '0', CEC => '0', CECARRYIN => '0',
      CECTRL => '0', CED => '0', CEINMODE => '0', CEM => '0',
      CEP            => en,
      -- resets
      RSTA => '0', RSTALLCARRYIN => '0', RSTALUMODE => '0', RSTB => '0',
      RSTC => '0', RSTCTRL => '0', RSTD => '0', RSTINMODE => '0', RSTM => '0',
      RSTP           => rst);

end architecture rtl;
