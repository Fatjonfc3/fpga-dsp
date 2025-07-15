library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity butterfly is
generic
(
	I_WIDTH : integer :=  16;
	O_WIDTH : integer := 16;
	CE_PER_CLK : integer := 1;
)
port 
(
	i_data_up , i_data_low  : in std_logic_vector ( 2* (I_WIDTH ) - 1 downto 0 );
	i_valid : in std_logic;
	i_sync : in std_logic;
	ce : in std_logic;
	clk , rst : in std_logic;
	o_valid , o_sync : out std_logic;
	o_data_up , o_data_low : out std_logic_Vector ( 2 * ( O_WIDTH ) - 1 downto 0 )

);

architecture rtl of butterfly is

signal start : std_logic := '0';
--=====need to do some code refactoring and some better naming , but the overall idea is ok
signal reg_data_up_re , reg_data_up_im , reg_data_low_re , reg_data_low_im : signed ( I_WIDTH - 1 downto 0 ) := ( others => '0');

signal reg1_data_up_re , reg1_data_up_im , reg2_data_up_re , reg2_data_up_im : signed ( I_WIDTH - 1 + 1 downto 0) := ( others => '0'); --because we add , 1 bit plus
signal reg1_data_low_re , reg1_data_low_im : signed ( I_WIDTH - 1 + 1 downto 0) := ( others => '0'); --because we add , 1 bit plus

signal reg_Twiddle_Re , reg_twiddle_im , reg1_Twiddle_Re , reg1_twiddle_im : signed ( COEFF_WIDTH - 1 DOWNTO 0 ) := ( others => '0');

 signal reg1_intermediate_mul_re1 , reg1_intermediate_mul_re2 , reg2_intermediate_mul_re1 , reg2_intermediate_mul_re2: signed ( I_WIDTH + COEFF_WIDTH - 1 DOWNTO 0 ); --PROBABLY delay the reg1_data_low_im and twiddle rather then the full multiply til the end


signal reg_intermediate_sum_mul1  : signed ( I_WIDTH + 1 - 1 DOWNTO 0 ):= ( OTHERS => '0' );
signal reg_intermediate_sum_mul2 : signed ( COEFF_WIDTH + 1 -1 downto 0 ) := ( others => '0');
signal reg_intermediate_mul_3 : signed ( I_WIDTH + 1 + COEFF_WIDTH + 1 - 1 downto 0 ) := ( others => '0');

signal reg_Valid , reg_Valid1 , reg_valid2 , reg_Valid3 , reg_Valid_4 : std_logic := '0';

begin

--=================================================
--we need to substitute it with a general sync logic that maps the --
--first data of that block of data we want to do the fft
--===================================
START_LOGIC : process ( clk ) 
begin
if rising_edge ( clk )
	if valid = '1' and start ='0' then
		start = '1'
	end if;
end process START_LOGIC;


--====================== THIS will be the same apart if we want to reuse resources or not
PREPARE_DATA : process ( clk ) 
if rising_edge ( clk ) and  ( valid = '1' or start = '1' ) then
	--=====JUST SAMPLE=====
	reg_data_up_re <= signed (i_data_up ( 2* I_WIDTH - 1 downto I_WIDTH )); --or we could sample the whole input and put a comb circuit that gets specific parts, technically i guess it should be synthesized on the same way
	reg_data_up_im <= signed (i_data_up (I_WIDTH - 1 downto 0  ));
	reg_data_low_Re <= signed (i_data_low ( 2 * I_WIDTH - 1 downto  I_WIDTH));
	reg_data_low_im <=  signed (i_data_low ( I_WIDTH - 1 downto 0 ));

	reg_twiddle_re <= twiddle ( to_integer ( rd_counter))( 2* I_WIDTH - 1 downto I_WIDTH);
	reg_twiddle_im <= twiddle ( to_integer ( rd_counter))(  I_WIDTH - 1 downto 0);
	
	reg_valid <= '1';
--======== + 1 clock cycle=========
	reg1_data_up_re <= reg_data_up_re + reg_data_low_re;
	reg1_data_up_im <= reg_Data_up_im + reg_Data_low_im;
--we already have our up data ready , but we will need to delay it just to match the pipeline
	reg1_data_low_re <= reg_data_up_re - reg_data_low_re;
	reg1_data_low_im <= reg_Data_up_im - reg_Data_low_im;

	reg1_twiddle_re <= reg_twiddle_re;
	reg1_twiddle_im <= reg_twiddle_im;

	reg1_valid <= reg_Valid;
--======== + 1 clock cycle=========	
end if;
end process PREPARE_DATA;


NO_HW_REUSE : if ce_per_clk = 1 generate
process ( clk , rst)
if rising_Edge ( clk ) then
	if valid = '1' or start = '1' then 
	reg2_valid <= reg1_Valid;
	reg2_data_up_re <= reg1_data_up_re
	reg2_data_up_im <= reg1_data_up_im
	
	reg1_intermediate_mul_re1 <= reg1_data_low_re * reg1_twiddle_re; --1 dsp multiplier
	reg1_intermediate_mul_re2 <= reg1_data_low_im * reg1_twiddle_im; -- 1 dsp multiplier
	
	reg_intermediate_sum_mul1 <= reg1_data_low_re + reg1_data_low_im; -- additions ,  we do this just to lower the number of mul from 4 to 3 , but add some latency
	reg_intermediate_sum_mul2 <= reg1_twiddle_re + reg1_twiddle_im ;
	
--==========+1 clock cycle=======================
	reg3_valid <= reg2_Valid;
	reg3_data_up_re <= reg2_data_up_re
	reg3_data_up_re <= reg2_data_up_im
	
	reg2_intermediate_mul_re1 <= reg1_intermediate_mul_re1;
	reg2_intermediate_mul_re2 <= reg1_intermediate_mul_re2 ;

	reg_intermediate_mul_3 <= reg_intermediate_sum_mul1 * reg_intermediate_sum_mul2;

--=========== +1 clock cycle , put the data to the output
	reg4_valid <= reg3_Valid;
	o_data_up_re <= reg3_data_up_re ;
	o_data_up_im <= reg3_Data_up_im
	
	o_data_low_re <= reg2_intermediate_mul_re1 - reg2_intermediate_mul_re2 ;
	o_data_low_im <= reg_intermediate_mul_3 - reg2_intermediate_mul_re1 - reg2_intermediate_mul_re2;

--====total 5 clock cycles
end if;
end if;
end process;
end generate NO_HW_REUSE;


end architecture rtl;
