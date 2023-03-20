library IEEE;
use IEEE.std_logic_1164.all;	  
use ieee.numeric_std.all;

entity mic_receiver is
	 port(
	 	 clk : in STD_LOGIC;
		 rst : in STD_LOGIC := '0';
		 pdm : in STD_LOGIC;
		 counter : in std_logic_vector(15 downto 0);
		 ready : out STD_LOGIC;
		 dout : out STD_LOGIC_VECTOR(15 downto 0)
	     );
end mic_receiver;

--}} End of automatically maintained section

architecture mic_receiver of mic_receiver is

constant b_max1 : integer := 128;
constant b_max2 : integer := 1024;
constant b_max3 : integer := 4096;
constant b_max4 : integer := 16382;
constant b_max5 : integer := 32768;
constant b_max6 : integer := 65536;
type delay_line is array (0 to 3) of integer range -2*b_max6 to 2*b_max6;

signal i1_var : integer range -2*b_max1 to 2*b_max1;
signal i2_var : integer range -2*b_max2 to 2*b_max2;
signal i3_var : integer range -2*b_max3 to 2*b_max3;
signal i4_var : integer range -2*b_max4 to 2*b_max4;
signal i5_var : integer range -2*b_max5 to 2*b_max5;
signal i6_var : integer range -2*b_max6 to 2*b_max6;
signal delay1 : delay_line;
signal delay2 : delay_line;
signal delay3 : delay_line;
signal delay4 : delay_line;
signal delay5 : delay_line;
signal delay6 : delay_line;

begin

filter: process(clk, rst)	  
begin
	if rst='1' then
		i1_var <= 0;
		i2_var <= 0;
		i3_var <= 0;
		i4_var <= 0;
		i5_var <= 0;
		i6_var <= 0;
		delay1 <= (0,0,0,0);
		delay2 <= (0,0,0,0);
		delay3 <= (0,0,0,0);
		delay4 <= (0,0,0,0);
		delay5 <= (0,0,0,0);
		delay6 <= (0,0,0,0);
		ready <= '0';
		dout <= (others => '0');
	elsif rising_edge(clk) then
		
		if counter(3 downto 0)=b"1111" then -- STAGE 1
            if pdm='1' then
                if i1_var < b_max1 then
                    i1_var <= i1_var + 20;
                else
                    i1_var <= b_max1;
                end if;
            else
                if i1_var > - b_max1 then
                    i1_var <= i1_var - 20;
                else
                    i1_var <= -b_max1;
                end if;
            end if;
            
            delay1(3) <= delay1(2);
            delay1(2) <= delay1(1);
            delay1(1) <= i1_var; 
        end if;

		if counter(4 downto 0)=b"11111" then -- STAGE 2
			if i1_var-delay1(3)>0 then
				if i2_var < b_max2 then
					i2_var <= i2_var + 2*i1_var - 2*delay1(3);
				else
					i2_var <= b_max2;
				end if;
			else
				if i2_var > - b_max2 then
					i2_var <= i2_var + 2*i1_var - 2*delay1(3);
				else
					i2_var <= -b_max2;
				end if;
			end if;
			
			delay2(3) <= delay2(2);
			delay2(2) <= delay2(1);
			delay2(1) <= i2_var;
		end	if;
		
		if counter(5 downto 0)=b"111111" then -- STAGE 3
			if i2_var-delay2(3)>0 then
				if i3_var < b_max3 then
					i3_var <= i3_var + 2*i2_var - 2*delay2(3);
				else
					i3_var <= b_max3;
				end if;
			else
				if i3_var > - b_max3 then
					i3_var <= i3_var + 2*i2_var - 2*delay2(3);
				else
					i3_var <= -b_max3;
				end if;
			end if;
			
			delay3(3) <= delay3(2);
			delay3(2) <= delay3(1);
			delay3(1) <= i3_var; 		
		end	if;

		if counter(6 downto 0)=b"1111111" then -- STAGE 4
			if i3_var-delay3(3)>0 then
				if i4_var < b_max4 then
					i4_var <= i4_var + 2*i3_var - 2*delay3(3);
				else
					i4_var <= b_max4;
				end if;
			else
				if i4_var > - b_max4 then
					i4_var <= i4_var + 2*i3_var - 2*delay3(3);
				else
					i4_var <= -b_max4;
				end if;
			end if;
			
			delay4(3) <= delay4(2);
			delay4(2) <= delay4(1);
			delay4(1) <= i4_var;
		end	if;
		
		if counter(7 downto 0)=b"11111111" then -- STAGE 5
			if i4_var-delay4(3)>0 then
				if i5_var < b_max5 then
					i5_var <= i5_var + i4_var - delay4(3);
				else
					i5_var <= b_max5;
				end if;
			else
				if i5_var > - b_max5 then
					i5_var <= i5_var + i4_var - delay4(3);
				else
					i5_var <= -b_max5;
				end if;
			end if;
			
			delay5(3) <= delay5(2);
			delay5(2) <= delay5(1);
			delay5(1) <= i5_var;
		end	if;
		
		if counter(8 downto 0)=b"111111111" then -- STAGE 6
			if i5_var-delay5(3)>0 then
				if i6_var < b_max4 then
					i6_var <= i6_var + 2*i5_var - 2*delay5(3);
				else
					i6_var <= b_max6;
				end if;
			else
				if i6_var > - b_max6 then
					i6_var <= i6_var + 2*i5_var - 2*delay5(3);
				else
					i6_var <= -b_max6;
				end if;
			end if;
			
			delay6(3) <= delay6(2);
			delay6(2) <= delay6(1);
			delay6(1) <= i6_var;
            dout <= std_logic_vector(to_signed(i5_var - delay5(3),16)); -- ?????????
		end	if;
        
   		if counter(8 downto 0)=b"000000000" then -- "ready" control
            ready <= '1';
        else
            ready <= '0';
        end if;
            
	end if;
end process;
	
end mic_receiver;
