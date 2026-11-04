-------------------------------------------------------------------------------
-- acc_ovf_fabric.vhd
--
-- MicroZed Chronicles: Flags for Free
--
-- The fabric reference for acc_ovf_dsp: a 48-bit accumulator, the range
-- check on the upper 48 - N bits, the clamp, and overflow and underflow
-- pulses with the same timing as the DSP48E2 pattern detector produces
-- (a pulse in the first out-of-range cycle, relative to the previous value).
-- Same ports and generics as acc_ovf_dsp so the two can be compared directly.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity acc_ovf_fabric is
  generic (
    N        : positive range 1 to 46 := 8;
    SATURATE : boolean := false
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    en        : in  std_logic;
    din       : in  std_logic_vector(47 downto 0);
    acc       : out std_logic_vector(47 downto 0);
    acc_sat   : out std_logic_vector(47 downto 0);
    in_range  : out std_logic;
    overflow  : out std_logic;
    underflow : out std_logic
  );
end entity acc_ovf_fabric;

architecture rtl of acc_ovf_fabric is

  function pos_limit(nbits : positive) return signed is   --  2**nbits - 1
    variable v : signed(47 downto 0) := (others => '0');
  begin
    v(nbits - 1 downto 0) := (others => '1');
    return v;
  end function pos_limit;

  constant C_POS_LIM : signed(47 downto 0) := pos_limit(N);
  constant C_NEG_LIM : signed(47 downto 0) := not pos_limit(N);   -- -2**N
  constant C_ZEROS   : std_logic_vector(47 downto N) := (others => '0');
  constant C_ONES    : std_logic_vector(47 downto N) := (others => '1');

  signal p        : signed(47 downto 0) := (others => '0');
  signal p_clamp  : signed(47 downto 0);
  signal pd, pbd  : std_logic := '0';   -- registered with p
  signal pd_prev  : std_logic := '0';   -- one cycle older, for the pulses
  signal pbd_prev : std_logic := '0';
  signal p_fresh  : std_logic := '1';   -- P is zero from reset (see acc_ovf_dsp)
  signal inr      : std_logic;

begin

  -- the flags are reset low to mirror the DSP48E2, whose PATTERNDETECT
  -- registers come out of reset low regardless of P, so the same p_fresh
  -- flag is needed here to report the reset value of zero as in range
  inr     <= pd or pbd or p_fresh;
  p_clamp <= p         when inr = '1' else
             C_NEG_LIM when p(47) = '1' else
             C_POS_LIM;

  process (clk)
    variable base : signed(47 downto 0);
    variable nxt  : signed(47 downto 0);
    variable hi   : std_logic_vector(47 downto N);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p        <= (others => '0');
        pd       <= '0';
        pbd      <= '0';
        pd_prev  <= '0';
        pbd_prev <= '0';
        p_fresh  <= '1';
      elsif en = '1' then
        p_fresh  <= '0';
        if SATURATE then
          base := p_clamp;             -- continue from the limit
        else
          base := p;
        end if;
        nxt := base + signed(din);
        hi  := std_logic_vector(nxt(47 downto N));
        p   <= nxt;
        if hi = C_ZEROS then pd <= '1'; else pd <= '0'; end if;
        if hi = C_ONES  then pbd <= '1'; else pbd <= '0'; end if;
        pd_prev  <= pd;
        pbd_prev <= pbd;
      end if;
    end if;
  end process;

  acc       <= std_logic_vector(p);
  acc_sat   <= std_logic_vector(p_clamp);
  in_range  <= inr;
  overflow  <= (not pd) and (not pbd) and pd_prev;
  underflow <= (not pd) and (not pbd) and pbd_prev;

end architecture rtl;
