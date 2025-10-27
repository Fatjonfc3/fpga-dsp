library IEEE;

use IEEE.numeric_std.all;
use IEEE.std_logic_1164.all;
use IEEE.math_real.all;

entity fft_stage_embedded is
generic (
	I_WIDTH : integer := 16;
	O_WIDTH : integer := 17; --techncically each stage increments by 1 max , bcs of the addition , multiplication doesn't really impact because numbers smaller then 1 , just be careful on rounding there
	STAGE : integer := 1;
	N : integer := 32; 
	DEPTH_2 : integer := 16; -- DEPTH = N / 2**STAGE
    COEFF_WIDTH : integer := 16;
    COEFF_FRACTIONAL_POINT : integer := 8;

);
port (
	clk , rst : in std_logic;
	ce : in std_logic;
	i_sync : in std_logic;
	o_sync : out std_logic;
	data_in : in std_logic_vector ( (2 * I_WIDTH) - 1 downto 0 ); --because we have the first I_width bit real number the next ones imaginary number
    o_Ce : out std_logic;
	data_out : out std_logic_vector ( (2* O_WIDTH) - 1 downto 0 )

);
end entity fft_stage_embedded;

architecture rtl of fft_stage_embedded is
constant DEPTH : integer := N / (2 **STAGE );
--=========================Counters=======================================
signal i_buf_cnt : unsigned ( integer(ceil(log2(real(DEPTH)))) - 1 + 1 downto 0 ) := ( others => '0'); -- by adding an extra bit we use the MSB to differentiate if we it's the time we need to write to the buffer or read from it
-- signal i_buf_cnt : unsigned ( ( N/ 2**S ) - 1 + 1 downto 0 ) := ( others => '0'); 
signal o_buf_cnt : unsigned  ( integer (ceil(log2(real(DEPTH)))) - 1 + 1 downto 0 ) := ( others => '0'); -- same depth because for each input there are 2 outputs
-- we know that everything is 2**N so the log will be an integer so no need to ceil it,but just in case
--=======================Buffers for input and output ========================
type t_i_buf is array ( 0 to DEPTH - 1 ) of signed ( (2 * I_WIDTH) - 1 downto 0 );
type t_o_buf is array ( 0 to DEPTH - 1 ) of signed ((2 * O_WIDTH) - 1 downto 0 );

signal i_buf : t_i_buf := ( others => ( others => '0'));

signal o_buf : t_o_buf := ( others => ( others => '0'));
--===============

constant UP_LOW_BIT_WIDTH : integer := I_WIDTH +1 ;
constant LOW_PREP_WIDTH : integer := UP_LOW_BIT_WIDTH + 1;
signal a , b : signed ( LOW_PREP_WIDTH - 1 downto 0 ) := ( others => '0'); 
--testing
--========SIGNALS WE WILL PASS TO THE BUTTERFLY OPERATION
signal b_i_up , b_i_down : signed ( 2*I_WIDTH - 1 downto 0 ):= ( others => '0'); 
signal b_i_valid : std_logic := '0';
--======Buttefly output regs=====================
signal b_o_up , b_o_up_reg, b_o_down : signed ((2 * O_WIDTH) - 1 downto 0 ):= ( others => '0');
signal b_o_valid : std_logic:= '0';
signal butterfly_sync : std_logic := '0';
--===== Signal for the delayed output , for the output that we get from the buffer
signal o_buffered : signed ((2 * O_WIDTH) - 1 downto 0 ):= ( others => '0');

--========Signal auxiliary for the sync
signal start : std_logic := '0';
signal b_o_valid_extended : std_logic := '0';
signal continue : std_logic := '0';

--===================
constant CE_PER_CLK : integer := 1;


signal ce_reg : std_logic := '0';
begin


butterfly : entity work.butterfly_2 
generic map (I_WIDTH => I_WIDTH , O_WIDTH => O_WIDTH , COEFF_WIDTH => COEFF_WIDTH , COEFF_FRACTIONAL_POINT => COEFF_FRACTIONAL_POINT , CE_PER_CLK => CE_PER_CLK , STAGE => STAGE , N => N )
port map ( I_DATA_UP => std_logic_vector ( B_I_UP )    , I_DATA_LOW => std_logic_vector (B_I_DOWN)  , CE => CE_reg , CLK => CLK ,O_VALID =>  B_O_VALID  ,  rst => rst, 
			signed (O_DATA_UP) => B_O_UP  , signed (O_DATA_LOW) => B_O_DOWN , i_Valid => b_i_Valid , i_sync => '0' , a=>a , b=>b
	);



--====Synchronization to the first data of the frame
process ( clk , rst)
begin
	if rising_Edge ( clk) then
		if i_sync = '1' or start = '1' then -- i_sync only one pulse, while we need start to have a stable 1 could also do like that

											--	start <= '1' when i_sync ='1' else
											--			start_Reg;

											-- process clk
											-- start_Reg <= start

												--sync_pipeline <= sync_pipeline(N-2 downto 0) & butterfly_sync; , nice pattern for sync , and not use many times different signals , nice
			start <= '1';
		end if;
		if i_buf_Cnt ( i_buf_cnt'high) = '1' and start = '1' then
			butterfly_sync <= '1';
			start <= '0';
		end if;
    end if;
			
	
end process  ;
--b_i_valid <= '1' when i_buf_Cnt ( i_buf_cnt'high) = '1' or i_buf_cnt ( i_buf_cnt'high - 1 downto 0) = ( i_buf_cnt'high - 1 downto 0 => '1') else
--			'0'; --hot fix
process(clk)
begin
if rising_edge ( clk ) then
ce_Reg <= ce;
end if;
end process;
--b_i_valid <= i_buf_Cnt ( i_buf_cnt'high);
INPUT_COUNTER : process ( clk , rst )
begin
	if rising_edge ( clk ) then
		if rst = '1' then
			i_buf_cnt <= ( others => '0' );
		elsif ce = '1' then
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
			if ( b_o_valid = '1' ) or ( continue = '0' and o_buf_cnt (o_buf_cnt'high) = '1' and ce = '1') then --because we say increase the counter when we have b_o_valid but also when it has finished the buterffly sending so we have our buffer full,so now we need to g through just for outputting them
				o_buf_cnt <= o_buf_cnt + 1;
			end if;
		end if;
     end if;
end process OUTPUT_COUNTER;


INPUT_INGEST : process ( clk , rst)
begin
	if rising_Edge ( clk ) then
		if rst = '1' then
			-- do nothing
		else
        	if ce = '1' then
			if (i_buf_cnt (i_buf_cnt'high) = '0') then
				i_buf ( to_integer ( i_buf_cnt (i_buf_cnt'high - 1 downto 0 ) )) <= signed ( data_in ); -- write to the input buffer
			end if;
		end if;
	end if;
end if;
end process INPUT_INGEST;

SEND_DATA_TO_BUTTERFLY_OPERATION : process ( clk , rst )
begin
	if rising_Edge ( clk ) then
		if rst = '1' then

		else
        	if ce = '1' then
			if (i_buf_cnt (I_buf_cnt'high) = '1' ) then
				b_i_up <= i_buf ( to_integer ( i_buf_cnt (i_buf_cnt'high - 1 downto 0 ) )); --since the msb changed value the other ones repeat
				b_i_down <= signed ( data_in );
				b_i_valid <= '1'; -- this will go to the ce input of butterfly
                --since this is a registered output so we send to the butterfly some registered output then we also registered ce so they are aligned at the butterfly operator
				
			else
            	b_i_valid <= '0';
             end if;
                
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
				o_buf ( to_integer ( o_buf_Cnt (o_buf_cnt'high - 1 downto 0))) <= b_o_down;
			end if;
		end if;
	end if;
end process BUFF_OUTPUT;

REG_THE_OUTPUT_OF_BUTTERFLY : process ( clk , rst)
begin
	if rising_edge ( clk ) then
		if rst = '1' then

		else 
			o_buffered <= o_buf ( to_integer ( o_buf_Cnt (o_buf_cnt'high - 1 downto 0))); --probably a bit of power consumption since there will alway be a read but still not a big deal i guess , just to be faster as soon as the msb has gone 1 the o_buffered has the correct data
		end if;
	end if;
end process REG_THE_OUTPUT_OF_BUTTERFLY;

--Add a sync signal since we need to keep track when the new frame started , so the new block of inputs we want to do the fft
-- o_sync <= (!oaddr[LGSPAN]) ? ob_sync : 1'b0; makes sense , we also would need to verify this design tbh , also add coefficients as an input
-- Add also the butterfly and start butterfly logic

EXTEND_B_O_VALID : process ( clk )
begin
if rising_edge ( clk ) then
	if rst = '1' then
    		b_o_valid_extended <= '0';
    else
    	if b_o_valid = '1' then
        	b_o_valid_extended <= b_o_valid;
         elsif ce = '1' then
         	b_o_valid_extended <= '0';
         end if;
     end if;
end if;
end process EXTEND_B_O_VALID;
--hot fix
process ( clk )
begin
if rising_edge ( clk ) then
	if b_o_valid = '1' then
    	b_o_up_reg <= b_o_up; --because butterfly outputs the value only for one clock cycle then it goes to 0, so we need to store it
    end if;
end if;
end process;

--it would be better to have o_ce and data_out registered / hot fix
process ( clk )
begin
if rising_edge ( clk ) then
    if rst = '1' then
    --	data_out <= ( others => '0');
     else
     		if  o_buf_cnt ( o_buf_cnt'high ) = '0'  or continue = '1' then
            	if  b_o_valid = '1' then  
            	data_out <= std_logic_vector ( b_o_up) ;
                elsif  b_o_valid_extended = '1'  then
                data_out <= std_logic_vector ( b_o_up_reg) ;
                end if;
             elsif o_buf_cnt ( o_buf_cnt'high) = '1' then
             	data_out <= std_logic_vector ( o_buffered);
           end if;
     end if;
end if;
end process;
-- hot fix             
process ( clk )
begin
if rising_edge ( clk ) then
if ce = '1' then
	if o_buf_cnt(o_buf_cnt'high) = '0' and o_buf_cnt (o_buf_cnt'high -1 downto 0 ) =  (o_buf_cnt'high -1 downto 0  => '1') then--we do this trick because when o_buf_cnt goes to 0111 it will wrap , and when it wraps bcs the msb goes to 1 we woudl directly output the buffered value and not the last value b_o_up , so wew control it via ce so we say our data won't change till the next ce comes , when next ce comes we just output the buffered_data, also the o_buf_cnt is controlled via ce bcs it increments so its fine,because at the same time the o_buf_cnt gets incremented
   		continue <= '1';
	else
  		continue <= '0';
	end if;
end if;
end if;
end process;
--data_out <=  std_logic_vector (b_o_up_reg)  when o_buf_cnt (o_buf_cnt'high) = '0' and  ( b_o_valid_extended = '1' or b_o_Valid ='1') else
--	    std_logic_vector ( o_buffered ) when o_buf_cnt (o_buf_cnt'high) = '1' else
--	    ( others => '0');
o_ce <= ce when i_buf_cnt ( i_buf_cnt'high ) = '1' or o_buf_cnt ( o_buf_cnt'high) = '1' else
		'0';        
end architecture rtl;
