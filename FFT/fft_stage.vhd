library IEEE;

use IEEE.numeric_std.all;
use IEEE.std_logic_1164.all;


entity fft_stage is
generic (
	I_WIDTH : integer := 16;
	O_WIDTH : integer := 17; --techncically each stage increments by 1 max , bcs of the addition , multiplication doesn't really impact because numbers smaller then 1 , just be careful on rounding there
	STAGE : integer := 1;
	N : integer := 32; 
	DEPTH : integer := 16;

)
port (
	clk , rst : in std_logic;
	ce : in std_logic;
	i_sync : in std_logic;
	o_sync : out std_logic;
	data_in : in std_logic_vector ( (2 * I_WIDTH) - 1 downto 0 ); --because we have the first I_width bit real number the next ones imaginary number
	data_out : out std_logic_vector ( (2* O_WIDTH) - 1 downto 0 )

);

architecture rtl of fft_stage is
--=========================Counters=======================================
signal i_buf_cnt : unsigned ( to_integer(log2(DEPTH)) - 1 + 1 downto 0 ) := ( others => '0'); -- by adding an extra bit we use the MSB to differentiate if we it's the time we need to write to the buffer or read from it
-- signal i_buf_cnt : unsigned ( ( N/ 2**S ) - 1 + 1 downto 0 ) := ( others => '0'); 
signal o_buf_cnt : unsigned  ( to_integer (log2(DEPTH)) - 1 + 1 downto 0 ) := ( others => '0'); -- same depth because for each input there are 2 outputs
-- we know that everything is 2**N so the log will be an integer so no need to ceil it
--=======================Buffers for input and output ========================
t_i_buf is type array ( 0 to DEPTH - 1 ) of signed ( (2 * I_WIDTH) - 1 downto 0 );
t_o_buf is type array ( 0 to DEPTH - 1 ) of signed ((2 * O_WIDTH) - 1 downto 0 );

signal i_buf : t_i_buf := ( others => ( others => '0'));

signal o_buf : t_o_buf := ( others => ( others => '0'));

--========SIGNALS WE WILL PASS TO THE BUTTERFLY OPERATION
signal b_i_up , b_i_down : signed ( 2*I_WIDTH - 1 downto 0 ):= ( others => '0'); 
signal b_i_valid : std_logic := '0';
--======Buttefly output regs=====================
signal b_o_up , b_o_down : signed ((2 * OWIDTH) - 1 downto 0 ):= ( others => '0');
signal b_o_valid : std_logic:= '0';

--===== Signal for the delayed output , for the output that we get from the buffer
signal o_buffered : signed ((2 * OWIDTH) - 1 downto 0 ):= ( others => '0');

--========Signal auxiliary for the sync
signal start : std_logic;
begin

--====Synchronization to the first data of the frame
process ( clk , rst)
begin
	if rising_Edge ( clk) then
		if i_sync = '1' or start = '1' then -- i_sync only one pulse, while we need start to have a stable 1 could also do like that
--
--	start <= '1' when i_sync ='1' else
--			start_Reg;
--
-- process clk
-- start_Reg <= start
--
--sync_pipeline <= sync_pipeline(N-2 downto 0) & butterfly_sync; , nice pattern for sync , and not use many times different signals , nice
			start <= '1';
		end if;
		if i_buf_Cnt ( i_buf_cnt'high) = '1' and start = '1' then
			butterfly_sync = '1';
			start <= '0';
		end if;
			
	
end process ;

INPUT_COUNTER : process ( clk , rst )
begin
	if rising_edge ( clk ) then
		if rst = '1' then
			i_buf_cnt <= ( others => '0' );
		else
			i_buf_cnt <= i_buf_Cnt + 1; -- we don't need to worry about wrapping it , since its a power of 2 so it perfectly matches
		end if;
	end if;

end process INPUT_COUNTER;

OUTPUT_COUNTER : process ( clk , rst )
begin
	if rising_Edge ( clk ) then
		if rst = '1' then
			o_Buf_Cnt <= ( others => '0');
		else
			if ( b_o_valid = '1' ) then
				o_buf_cnt <= o_buf_cnt + 1;
			end if;
		end if;
end process OUTPUT_COUNTER;

end process OUTPUT_COUNTER;
INPUT_INGEST : process ( clk , rst)
begin
	if rising_Edge ( clk ) then
		if rst = '1' then
			-- do nothing
		else
			if (i_buf_cnt (i_buf_cnt'high) = '0') then
				i_buf ( to_integer ( i_buf_cnt (log2(DEPTH) - 1 downto 0 ) ) <= signed ( data_in ); -- write to the input buffer
			end if;
		end if;
	end if;

end process INPUT_INGEST;

SEND_DATA_TO_BUTTERFLY_OPERATION : process ( clk , rst )
begin
	if rising_Edge ( clk ) then
		if rst = '1' then

		else
			if (i_buf_cnt (I_buf_cnt'high) = '1' ) then
				b_i_up <= i_buf ( to_integer ( i_buf_cnt (log2(DEPTH) - 1 downto 0 ) ); --since the msb changed value the other ones repeat
				b_i_down <= signed ( data_in );
				b_i_valid <= '1';
				
			end if;
		end if;
	end if;
end process SEND_DATA_TO_BUTTERFLY_OPERATION;

BUFF_OUTPUT : process ( clk  , rst )
begin
	if rising_Edge ( clk ) then
		if rst then

		else
			if b_o_valid = '1' then
				o_buf ( to_integer ( o_buf_Cnt (log2 (DEPTH) - 1 downto 0))) <= b_o_down;
			end if;
		end if;
	end if;
end process BUFF_OUTPUT

REG_THE_OUTPUT_OF_BUTTERFLY : process ( clk , rst)
begin
	if rising_edge ( clk ) then
		if rst = '1' then

		else 
			o_buffered <= o_buf ( to_integer ( o_buf_Cnt (log2 (DEPTH) - 1 downto 0))); --probably a bit of power consumption since there will alway be a read but still not a big deal i guess , just to be faster as soon as the msb has gone 1 the o_buffered has the correct data
		end if;
	end if;
end process REG_THE_OUTPUT_OF_BUTTERFLY;

--Add a sync signal since we need to keep track when the new frame started , so the new block of inputs we want to do the fft
-- o_sync <= (!oaddr[LGSPAN]) ? ob_sync : 1'b0; makes sense , we also would need to verify this design tbh , also add coefficients as an input
-- Add also the butterfly and start butterfly logic

data_out <= b_up when o_buf_cnt'high = '0' and b_valid = '1' else
	    o_buffered when o_buf_cnt'high = '1' else
	    ( others => '0');
end architecture rtl;
