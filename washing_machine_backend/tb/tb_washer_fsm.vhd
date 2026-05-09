library ieee;
use ieee.std_logic_1164.all;
use std.env.finish;

entity tb_washer_fsm is
end tb_washer_fsm;

architecture sim of tb_washer_fsm is

    component washer_fsm is
        port(
            clk        : in  std_logic;
            reset      : in  std_logic;
            start      : in  std_logic;
            fill_valve : out std_logic;
            motor      : out std_logic;
            pump       : out std_logic;
            done_led   : out std_logic
        );
    end component;

    signal clk        : std_logic := '0';
    signal reset      : std_logic := '0';
    signal start      : std_logic := '0';

    signal fill_valve : std_logic;
    signal motor      : std_logic;
    signal pump       : std_logic;
    signal done_led   : std_logic;

    constant CLK_PERIOD : time := 10 ns;

begin

    uut : entity work.washer_fsm
        generic map (
            CLK_FREQ_HZ => 10
        )
        port map(
            clk        => clk,
            reset      => reset,
            start      => start,
            fill_valve => fill_valve,
            motor      => motor,
            pump       => pump,
            done_led   => done_led
        );

    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    stim_proc : process
    begin
        reset <= '1';
        start <= '0';
        wait for 30 ns;

        reset <= '0';
        wait for 20 ns;

        start <= '1';
        wait for 10 ns;
        start <= '0';

        wait for 2500 ns;

        report "End of simulation" severity note;
        finish;
    end process;

end sim;