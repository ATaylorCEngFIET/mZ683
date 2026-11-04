-------------------------------------------------------------------------------
-- tb_acc_ovf.vhd
--
-- Self-checking testbench for the overflow-detecting accumulator. USE_DSP
-- selects acc_ovf_dsp (UNISIM, Vivado xsim) or acc_ovf_fabric (GHDL).
-- SATURATE is passed to the DUT.
--
-- Stimulus (N = 8, valid range -256 .. 255): accumulate +60 for seven cycles,
-- -60 for fifteen cycles, then 0. An integer reference model predicts P, the
-- clamped value, in_range and the overflow / underflow pulses every cycle and
-- the testbench compares, printing a trace table for the article.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_acc_ovf is
  generic (
    USE_DSP  : boolean := false;
    SATURATE : boolean := false;
    N        : positive := 8
  );
end entity tb_acc_ovf;

architecture sim of tb_acc_ovf is

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal en        : std_logic := '0';
  signal din       : std_logic_vector(47 downto 0) := (others => '0');
  signal acc       : std_logic_vector(47 downto 0);
  signal acc_sat   : std_logic_vector(47 downto 0);
  signal in_range  : std_logic;
  signal overflow  : std_logic;
  signal underflow : std_logic;
  signal done      : boolean := false;

  constant POS_LIM : integer :=  2**N - 1;
  constant NEG_LIM : integer := -(2**N);

begin

  clk <= not clk after 5 ns when not done else '0';

  g_dsp : if USE_DSP generate
    dut : entity work.acc_ovf_dsp
      generic map (N => N, SATURATE => SATURATE)
      port map (clk => clk, rst => rst, en => en, din => din, acc => acc,
                acc_sat => acc_sat, in_range => in_range,
                overflow => overflow, underflow => underflow);
  end generate g_dsp;

  g_fab : if not USE_DSP generate
    dut : entity work.acc_ovf_fabric
      generic map (N => N, SATURATE => SATURATE)
      port map (clk => clk, rst => rst, en => en, din => din, acc => acc,
                acc_sat => acc_sat, in_range => in_range,
                overflow => overflow, underflow => underflow);
  end generate g_fab;

  stim : process
    variable cyc      : integer := 0;
    variable errors   : integer := 0;
    -- reference model state
    variable ref_p    : integer := 0;
    variable ref_pd   : boolean := false;   -- P in 0 .. POS_LIM
    variable ref_pbd  : boolean := false;   -- P in NEG_LIM .. -1
    variable ref_pdq  : boolean := false;   -- previous cycle
    variable ref_pbdq : boolean := false;
    variable ref_fresh: boolean := true;    -- P still holds its reset value
    variable ref_clamp: integer;
    variable ref_ovf  : boolean;
    variable ref_udf  : boolean;
    variable addend   : integer;
    variable got_p, got_s : integer;

    function b2sl(b : boolean) return std_logic is
    begin
      if b then return '1'; else return '0'; end if;
    end function b2sl;

    procedure step(a : integer) is
      variable base : integer;
    begin
      -- drive the addend for the coming rising edge
      din <= std_logic_vector(to_signed(a, 48));
      -- reference model update
      if ref_pd or ref_pbd or ref_fresh then
        ref_clamp := ref_p;
      elsif ref_p < 0 then
        ref_clamp := NEG_LIM;
      else
        ref_clamp := POS_LIM;
      end if;
      if SATURATE then base := ref_clamp; else base := ref_p; end if;
      ref_p     := base + a;
      ref_fresh := false;
      ref_pdq   := ref_pd;
      ref_pbdq  := ref_pbd;
      ref_pd    := ref_p >= 0 and ref_p <= POS_LIM;
      ref_pbd   := ref_p < 0 and ref_p >= NEG_LIM;
      ref_ovf   := not ref_pd and not ref_pbd and ref_pdq;
      ref_udf   := not ref_pd and not ref_pbd and ref_pbdq;
      if ref_pd or ref_pbd then
        ref_clamp := ref_p;
      elsif ref_p < 0 then
        ref_clamp := NEG_LIM;
      else
        ref_clamp := POS_LIM;
      end if;
      -- sample mid-cycle after the edge
      wait until falling_edge(clk);
      cyc   := cyc + 1;
      got_p := to_integer(signed(acc(31 downto 0)));
      got_s := to_integer(signed(acc_sat(31 downto 0)));
      report "cyc " & integer'image(cyc)
           & "  din " & integer'image(a)
           & "  P " & integer'image(got_p)
           & "  sat " & integer'image(got_s)
           & "  inr " & std_logic'image(in_range)
           & "  ovf " & std_logic'image(overflow)
           & "  udf " & std_logic'image(underflow);
      if got_p /= ref_p or got_s /= ref_clamp or in_range /= b2sl(ref_pd or ref_pbd or ref_fresh)
         or overflow /= b2sl(ref_ovf) or underflow /= b2sl(ref_udf) then
        report "ERROR: expected P " & integer'image(ref_p) & " sat "
             & integer'image(ref_clamp) & " inr " & std_logic'image(b2sl(ref_pd or ref_pbd or ref_fresh))
             & " ovf " & std_logic'image(b2sl(ref_ovf))
             & " udf " & std_logic'image(b2sl(ref_udf)) severity error;
        errors := errors + 1;
      end if;
    end procedure step;
  begin
    wait for 150 ns;                 -- clear of the UNISIM GSR window
    wait until falling_edge(clk);
    rst <= '0';
    en  <= '1';

    for i in 1 to 7  loop step( 60); end loop;
    for i in 1 to 15 loop step(-60); end loop;
    for i in 1 to 3  loop step(  0); end loop;

    -- second scenario: reset, then leave the range on the very first
    -- accumulation. The previous-cycle flag inside the slice was reset low,
    -- so no OVERFLOW pulse is expected; in_range still reports it.
    report "-- reset, then +300 as the first addend --";
    rst <= '1';
    wait until falling_edge(clk);
    rst <= '0';
    ref_p := 0; ref_pd := false; ref_pbd := false; ref_pdq := false;
    ref_pbdq := false; ref_fresh := true; cyc := 0;
    step(300);
    step(-60);
    step(-60);

    if errors = 0 then
      report "RESULT: PASS (SATURATE = " & boolean'image(SATURATE) & ")";
    else
      report "RESULT: FAIL, " & integer'image(errors) & " errors" severity error;
    end if;
    done <= true;
    wait;
  end process stim;

end architecture sim;
