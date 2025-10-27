library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

-- also for the multiplication ( a + jb) ( c + jd) = (ac-bd) + (ad + bc) j -> 4 mul, to lower that we do this
-- (a + b )(c + d) = ac + bd + ( ad + bc ) 1 mul  / ac 2 mul / bd 3 mul
-- (a + b )(c + d) - ac - bd = im part ac - bd = real part / we used just 3 mul
-- to check bit width , rounding , and better ways for pipeline , like just for the apperance better use just a n bit signal , and left shift it in each
--clock cycle for the valid or sync or whatever TODOO + Testing
entity butterfly_2 is
generic
(
	I_WIDTH : integer :=  16;
	O_WIDTH : integer := 16;
    COEFF_WIDTH : integer := 16;
    COEFF_FRACTIONAL_POINT : integer := 15;
	CE_PER_CLK : integer := 1;
    STAGE : integer := 1;
    N : integer := 256; --general fft N 
    
);
port 
(
	i_data_up , i_data_low  : in std_logic_vector ( 2* (I_WIDTH ) - 1 downto 0 );
	i_valid : in std_logic;
	i_sync : in std_logic;
	ce : in std_logic;
	clk , rst : in std_logic;
	o_valid , o_sync : out std_logic;
    a , b : out signed ( I_WIDTH +1 + 1 - 1 downto 0  );
	o_data_up , o_data_low : out std_logic_Vector ( 2 * ( O_WIDTH ) - 1 downto 0 )

);
end entity butterfly_2;
architecture rtl of butterfly_2 is

constant DEPTH : integer := ( integer (ceil(real(N / 2**STAGE)))) ;
constant DEPTH_2 : integer := ( integer (ceil(log2(real(N / 2**STAGE))))) ;
constant STAGE_2 : integer := STAGE - 1 ; 
constant N_STAGE : integer :=  ( integer (ceil(log2(real(N / 2**STAGE_2)))));
constant UP_LOW_BIT_WIDTH : integer := I_WIDTH +1 ;
constant LOW_PREP_WIDTH : integer := UP_LOW_BIT_WIDTH + 1;
constant COEFF_ADD : integer := COEFF_WIDTH + 1;
constant reuse_logic : integer := coeff_add + low_prep_width - 1;
constant SCALE : real := 2.0**COEFF_FRACTIONAL_POINT;
constant coeff_mul_SIZE : integer := 2 * COEFF_WIDTH;

type t_twiddle is array (0 to integer ( ceil ( real ( N/(2 **STAGE) ))) - 1) of signed ( 2*COEFF_WIDTH - 1 downto 0);


--===========================	Make twiddle function
function float_to_signed ( x : real ; width : integer ) return signed  is
variable scaled : integer;
variable max_val : integer := 2**(width-1) - 1;
variable min_val : integer := -2**(width-1);
variable s : signed(width-1 downto 0);
begin
scaled :=integer ( round( x * SCALE));
if scaled > max_val then
	scaled := max_val;
elsif scaled < min_val then
	scaled := min_val;
end if;
s := to_signed (scaled,width);
return s;
end function;

function make_twiddle return t_twiddle is 
variable arr : t_twiddle := ( others => ( others => '0'));
variable angle : real;
variable  im , re : real;
variable  i : integer;
begin
for i in 0 to DEPTH - 1 loop
angle := (math_pi * (- 2.0) * real(i) ) / real ( 8 ); --n_Stag
re := cos (angle);
im := sin ( angle);
--arr(i) := to_signed(integer(re), COEFF_WIDTH) &
 --         to_signed(integer(im), COEFF_WIDTH);

arr (i) := float_to_signed ( re , COEFF_WIDTH ) & float_to_signed (im , COEFF_WIDTH);
end loop;
return arr;
end function make_twiddle;




--===========================================
--signal twiddle : t_twiddle  := ( others => ( others => '0'));
signal twiddle : t_twiddle := make_twiddle;
type t_state is ( IDLE , LOAD , PROCESS_DATA , FINAL_PROCESS);

signal state : t_state := IDLE ;

signal start : std_logic := '0'; --because in the preparation stage we sample the input and do the pre adding for the up stage and pre sub
--=====need to do some code refactoring and some better naming , but the overall idea is ok
signal reg_data_up_re , reg_data_up_im , reg_data_low_re , reg_data_low_im : signed ( I_WIDTH - 1 downto 0 ) := ( others => '0');

signal reg1_data_up_re , reg1_data_up_im : signed ( I_WIDTH - 1 + 1 downto 0) := ( others => '0'); --because we add , 1 bit plus
signal reg1_data_low_re , reg1_data_low_im : signed ( I_WIDTH - 1 + 1 downto 0) := ( others => '0'); --because we add , 1 bit plus

signal reg_Twiddle_Re , reg_twiddle_im  : signed ( COEFF_WIDTH - 1 DOWNTO 0 ) := ( others => '0');
--, reg1_Twiddle_Re , reg1_twiddle_im
--============================Mul Signals 

signal reg_sum_low : signed ( LOW_PREP_WIDTH - 1 downto 0 ) := ( others => '0'); --+ 1 clock cycle

signal reg_sum_twiddle : signed ( COEFF_ADD - 1 downto 0 ) := ( others => '0');

--signal	reg_mul_hw_reuse1 , reg_mul_hw_reuse2 : signed ( COEFF_ADD * 3 - 1  downto 0) := ( OTHERS => '0');
signal	reg_mul_hw_reuse1 , reg_mul_hw_reuse2 : signed ( LOW_PREP_WIDTH * 3 - 1  downto 0) := ( OTHERS => '0');
signal tb_h_1_1 , tb_h_2_2 : signed ( reg_sum_low'length - 1 downto 0 ):= ( others => '0'); 

--basically we say we will concat 3 signals here low_re , low_im , sum_low , since sum_low has the longest bit width and we need to align them let's allocate 3 * longe st_bit_width , a bit of extra bits

signal reg_intermediate_mul : signed ( 2 * LOW_PREP_WIDTH - 1 downto 0 ):= ( others => '0');
signal mul_h : signed ( reg_intermediate_mul'length - 1 downto 0):= ( others => '0');
-- LOW_PREP_WIDTH + COEFF_ADD

signal	reg_mul_low_re_twiddle_re :  signed ( UP_LOW_BIT_WIDTH + COEFF_WIDTH - 1 downto 0 ):= ( others => '0');
signal 	reg_mul_low_im_twiddle_im :  signed ( UP_LOW_BIT_WIDTH + COEFF_WIDTH - 1 downto 0 ):= ( others => '0');
signal	reg_mul_sum_low_sum_twiddle : signed (LOW_PREP_WIDTH  + COEFF_WIDTH - 1 downto 0 ):= ( others => '0');

signal 	reg_low_result_im : signed ( UP_LOW_BIT_WIDTH + COEFF_WIDTH  + 1 - 1  downto 0):= ( others => '0'); 
signal 	reg_low_result_re :  signed (LOW_PREP_WIDTH  + COEFF_WIDTH + 1 - 1  downto 0 ):= ( others => '0'); 
--signal	reg_low_result_re : signed ( I_WIDTH + 1 + 1 + COEFF_WIDTH - 1 + 1 downto 0 ):= ( others => '0'); -- we could also add an extra bit here 

--===============================



signal start_fsm : std_logic := '0';
signal reg1_sync : std_logic := '0';
signal fsm_o : std_logic := '0';

signal phase : unsigned ( 1 downto 0) := ( others => '0');
signal rd_counter : unsigned ( DEPTH_2 - 1 downto 0  ) := ( others => '0');

begin

--=================================================
--we need to substitute it with a general sync logic that maps the --
--first data of that block of data we want to do the fft
--===================================
START_LOGIC : process ( clk ) 
begin
if rising_edge ( clk ) then
	if ce = '1' and i_valid = '1' then
		start <= '1';
	else 
    	start <= '0';
    end if;
end if;
    -- we also need to reset start at some point
end process START_LOGIC;


--====================== THIS will be the same apart if we want to reuse resources or not
PREPARE_DATA : process ( clk ) --+2 clock cycle
begin
if rising_edge ( clk )  then
	--=====JUST SAMPLE=====
    start_fsm <= '0';
    
	
    
    if ce = '1' and i_valid = '1' then
    reg1_sync <= i_sync;
	reg_data_up_re <= signed (i_data_up ( 2* I_WIDTH - 1 downto I_WIDTH )); --or we could sample the whole input and put a comb circuit that gets specific parts, technically i guess it should be synthesized on the same way
	reg_data_up_im <= signed (i_data_up (I_WIDTH - 1 downto 0  ));
	
    reg_data_low_Re <= signed (i_data_low ( 2 * I_WIDTH - 1 downto  I_WIDTH));
	reg_data_low_im <=  signed (i_data_low ( I_WIDTH - 1 downto 0 ));

	reg_twiddle_re <= twiddle ( to_integer ( rd_counter))( 2* COEFF_WIDTH - 1 downto COEFF_WIDTH);
	reg_twiddle_im <= twiddle ( to_integer ( rd_counter))(  COEFF_WIDTH - 1 downto 0);
	

    elsif start = '1' then
--======== + 1 clock cycle=========
	reg1_data_up_re <= resize ( reg_data_up_re , reg1_data_up_re'length )  + resize ( reg_data_low_re , reg1_data_up_re'length ) ;
	reg1_data_up_im <= resize ( reg_Data_up_im , reg1_data_up_im'length ) + resize (reg_Data_low_im , reg1_data_up_im'length );
--we already have our up data ready , but we will need to delay it just to match the pipeline
	reg1_data_low_re <= resize ( reg_data_up_re , reg1_data_low_re'length) - resize ( reg_data_low_re , reg1_data_low_re'length );
	reg1_data_low_im <= resize ( reg_Data_up_im , reg1_data_low_im'length) - resize ( reg_Data_low_im, reg1_data_low_im'length);

	--we could increment rd_counter here
    rd_counter <= rd_counter + 1;

	
    start_fsm <= '1';
    end if;
--======== + 1 clock cycle=========	
end if;
end process PREPARE_DATA;


fsm_control : process ( clk  , rst)
begin
if rising_Edge ( clk ) then
	if rst = '1' then
		state <= IDLE;
	else
	fsm_o <= '0';
		case state is 
	when IDLE =>
		if start_fsm = '1' then
			reg_sum_low <= resize ( reg1_data_low_re , reg_sum_low'length ) +  resize ( reg1_data_low_im ,reg_sum_low'length ) ; --+ 1 clock cycle
			reg_sum_twiddle <=resize (  reg_twiddle_re , reg_sum_twiddle'length )  + resize ( reg_twiddle_im , reg_sum_twiddle'length );
			state <= LOAD;
		end if;
	when LOAD => 
	--	reg_mul_hw_reuse1 <= resize ( reg1_data_low_re, reg_sum_twiddle'length) & resize ( reg1_data_low_im , reg_sum_twiddle'length) & resize ( reg_sum_low , reg_sum_twiddle'length ) ; --+ 1 clock cycle
	--	reg_mul_hw_reuse2 <= resize ( reg_twiddle_re , reg_sum_twiddle'length ) & resize ( reg_twiddle_im , reg_sum_twiddle'length ) & resize (  reg_sum_twiddle , reg_sum_twiddle'length ) ;
		state <= PROCESS_DATA;
        reg_mul_hw_reuse1 <= resize ( reg1_data_low_re, reg_sum_low'length) & resize ( reg1_data_low_im , reg_sum_low'length) & resize ( reg_sum_low , reg_sum_low'length ) ; --+ 1 clock cycle
		reg_mul_hw_reuse2 <= resize ( reg_twiddle_re , reg_sum_low'length ) & resize ( reg_twiddle_im , reg_sum_low'length ) & resize (  reg_sum_twiddle , reg_sum_low'length) ;
        
		
	when PROCESS_DATA =>
		phase <= phase + 1;
		-- left shift the registers of mul hw reuse -- --+ 3 clock cycle
        --substitutes reg_sum_Twiddle with reg_sum_low
		reg_mul_hw_reuse1 <= reg_mul_hw_reuse1 (reg_mul_hw_reuse1'high -  reg_sum_low'length  downto 0  ) & (reg_mul_hw_reuse1'high downto reg_mul_hw_reuse1'high -  reg_sum_low'length + 1   => '0');
        reg_mul_hw_reuse2 <= reg_mul_hw_reuse2 (reg_mul_hw_reuse2'high -  reg_sum_low'length  downto 0  ) & (reg_mul_hw_reuse2'high downto reg_mul_hw_reuse2'high - reg_sum_low'length + 1  => '0');
        reg_intermediate_mul <= signed ( reg_mul_hw_reuse1 ( reg_mul_hw_reuse1'high downto reg_mul_hw_reuse1'high  - reg_sum_low'high )) * signed (reg_mul_hw_reuse2 ( reg_mul_hw_reuse2'high downto reg_mul_hw_reuse1'high  - reg_sum_low'high));
        
			if phase = 1 then --considering the phase
				reg_mul_low_re_twiddle_re <= signed (reg_intermediate_mul(reg_intermediate_mul'high) & resize ( reg_intermediate_mul , reg_mul_low_re_twiddle_re'length - 1 )) ;
			elsif phase = 2 then
				reg_mul_low_im_twiddle_im <= signed (reg_intermediate_mul(reg_intermediate_mul'high) & resize ( reg_intermediate_mul , reg_mul_low_im_twiddle_im'length - 1 ));
				
			elsif phase = 3 then
				reg_mul_sum_low_sum_twiddle <= signed (reg_intermediate_mul(reg_intermediate_mul'high) & resize ( reg_intermediate_mul , reg_mul_sum_low_sum_twiddle'length - 1 ));
				state <= final_process;
				phase <=  ( others => '0');
			end if;
            --no need for rounding here because the reg_intermediate_mul is bigger or equal to all the other values
			
	when FINAL_PROCESS => 
		-- +2 clock cycles
		phase <= phase + 1;
		if phase = 0 then
			reg_low_result_im <= signed (resize( reg_mul_low_re_Twiddle_Re , reg_low_result_im'length ) - resize ( reg_mul_low_im_twiddle_im , reg_low_result_im'length ));
			reg_low_result_re <= signed ( resize ( reg_mul_sum_low_sum_twiddle, reg_low_result_re'length)  - resize ( reg_mul_low_re_Twiddle_Re , reg_low_result_re'length ));
		elsif phase = 1 then
			reg_low_result_re <= signed (resize ( reg_low_result_re, reg_low_result_re'length ) - resize ( reg_mul_low_im_twiddle_im , reg_low_result_re'length )) ;
			phase <= ( others => '0');
			state <= IDLE;
			fsm_o <= '1';	
		end if;
	end case;
end if;
end if;
end process fsm_Control;

process ( clk , rst)
begin
if rising_edge ( clk ) then
	if rst = '1' then
    
    else
    	if fsm_o = '1' then
        	o_data_low <=std_logic_vector ( reg_low_result_re (reg_low_result_re'high ) & reg_low_result_re ( COEFF_FRACTIONAL_POINT + O_WIDTH - 1 - 1 DOWNTO  COEFF_FRACTIONAL_POINT ) &   reg_low_result_im (reg_low_result_im'high ) & reg_low_result_im ( COEFF_FRACTIONAL_POINT + O_WIDTH - 1 - 1 DOWNTO  COEFF_FRACTIONAL_POINT ));                    --10 clock cycles of delay so at leas a spacing of 10
            --double -1 cuz we have already got one as msb
            
  --       	o_data_up <= std_logic_vector ( reg1_data_up_re(reg1_data_up_Re'high) & reg1_data_up_re(reg1_data_up_Re'high - 1 downto reg1_data_up_Re'high - 1 - (O_WIDTH - 1 - 1)   )  & reg1_data_up_im(reg1_data_up_im'high) & reg1_data_up_im(reg1_data_up_im'high - 1 downto reg1_data_up_im'high - 1 - (O_WIDTH - 1 - 1)   ) );
                	o_data_up <= std_logic_vector ( reg1_data_up_re(reg1_data_up_Re'high) & resize (reg1_data_up_re , O_WIDTH - 1 )  & reg1_data_up_im(reg1_data_up_im'high) & resize ( reg1_data_up_im , O_WIDTH - 1 )) ;     
            
            -- here we can do some rounding 
            o_valid <= '1';
            o_sync <= reg1_sync;
        else
        o_valid <= '0';
        o_sync <= '0';
        o_data_low <= ( others => '0');
        
        o_data_up <= ( others => '0');
        end if;
    end if;
end if;
end process;

 tb_h_1_1 <= signed ( reg_mul_hw_reuse1 ( reg_mul_hw_reuse1'length - 1 downto reg_mul_hw_reuse1'length - 1  - (reg_sum_low'length - 1 ) ));
 tb_h_2_2 <= signed (reg_mul_hw_reuse2 ( reg_mul_hw_reuse2'length - 1 downto reg_mul_hw_reuse1'length - 1  - ( reg_sum_low'length - 1 ))) ; 
 a<=tb_h_1_1;
 b<=tb_h_2_2;
 mul_h <= resize ( tb_h_1_1  *tb_h_2_2 , mul_h'length )  ;


end architecture rtl;
