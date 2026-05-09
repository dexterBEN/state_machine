library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity washer_fsm is
    generic (
        CLK_FREQ_HZ : natural := 125_000_000
    );

    port(
        clk   : in  std_logic;   -- 125 MHz on PYNQ-Z2
        reset : in  std_logic;
        start : in  std_logic;

        fill_valve : out std_logic; -- LD0
        motor      : out std_logic; -- LD1
        pump       : out std_logic; -- LD2
        done_led   : out std_logic  -- LD3
    );
end washer_fsm;

architecture rtl of washer_fsm is

    type state_type is (IDLE, FILL, WASH, RINSE, SPIN, DONE);

    signal state      : state_type := IDLE;
    signal next_state : state_type := IDLE;

    signal state_counter : natural := 0;

    -- 1 Hz tick generator
    signal tick_counter : natural := 0;
    signal tick_1hz     : std_logic := '0';

    constant TICK_MAX : natural := CLK_FREQ_HZ - 1;

    -- durations in seconds
    constant FILL_TIME  : natural := 3;
    constant WASH_TIME  : natural := 5;
    constant RINSE_TIME : natural := 4;
    constant SPIN_TIME  : natural := 4;
    constant DONE_TIME  : natural := 3;

    -- start button synchronization + rising edge detection
    signal start_sync_0 : std_logic := '0';
    signal start_sync_1 : std_logic := '0';
    signal start_prev   : std_logic := '0';
    signal start_rising : std_logic := '0';

begin

    ----------------------------------------------------
    -- synchronize START button and detect rising edge
    ----------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            start_sync_0 <= '0';
            start_sync_1 <= '0';
            start_prev   <= '0';
            start_rising <= '0';
        elsif rising_edge(clk) then
            start_sync_0 <= start;
            start_sync_1 <= start_sync_0;

            start_rising <= start_sync_1 and not start_prev;
            start_prev   <= start_sync_1;
        end if;
    end process;

    ----------------------------------------------------
    -- 1 Hz tick generator
    ----------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            tick_counter <= 0;
            tick_1hz     <= '0';
        elsif rising_edge(clk) then
            if tick_counter = TICK_MAX then
                tick_counter <= 0;
                tick_1hz     <= '1';
            else
                tick_counter <= tick_counter + 1;
                tick_1hz     <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------
    -- state register
    ----------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    ----------------------------------------------------
    -- state duration counter
    ----------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            state_counter <= 0;
        elsif rising_edge(clk) then
            if state /= next_state then
                state_counter <= 0;
            elsif tick_1hz = '1' then
                state_counter <= state_counter + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------
    -- next-state logic
    ----------------------------------------------------
    process(state, start_rising, state_counter)
    begin
        next_state <= state;

        case state is
            when IDLE =>
                if start_rising = '1' then
                    next_state <= FILL;
                end if;

            when FILL =>
                if state_counter >= FILL_TIME then
                    next_state <= WASH;
                end if;

            when WASH =>
                if state_counter >= WASH_TIME then
                    next_state <= RINSE;
                end if;

            when RINSE =>
                if state_counter >= RINSE_TIME then
                    next_state <= SPIN;
                end if;

            when SPIN =>
                if state_counter >= SPIN_TIME then
                    next_state <= DONE;
                end if;

            when DONE =>
                if state_counter >= DONE_TIME then
                    next_state <= IDLE;
                end if;
        end case;
    end process;

    ----------------------------------------------------
    -- outputs as state LEDs, like Python STATE_LED
    --
    -- IDLE  = 0000
    -- FILL  = 0001
    -- WASH  = 0010
    -- RINSE = 0100
    -- SPIN  = 1000
    -- DONE  = 1111
    ----------------------------------------------------
    fill_valve <= '1' when (state = FILL  or state = DONE) else '0'; -- LD0
    motor      <= '1' when (state = WASH  or state = DONE) else '0'; -- LD1
    pump       <= '1' when (state = RINSE or state = DONE) else '0'; -- LD2
    done_led   <= '1' when (state = SPIN  or state = DONE) else '0'; -- LD3

end rtl;