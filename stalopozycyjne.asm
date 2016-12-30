.eqv		BUFF_OUT_SIZE 	1024
.eqv		BUFF_OUT_LIMIT 	1000
.eqv		BUFF_IN_SIZE	0xC0000
	
		.globl main
		.data
size:		.word 0	# rozmiar pliku bmp w pixelach
width:		.word 0 # szerokosc pliku bmp w pixelach
height:		.word 0	# wysokosc pliku bmp w pixelach
offset:		.word 0	# offset - początek tablicy pikseli
temp:		.word 0	# bufor wczytywania
buf_size:	.word 0 # do adresacji przy wielowczytywaniu

red_tmp:	.word 0
green_tmp:	.word 0
blue_tmp:	.word 0

		.align	2
buf_out:	.space  BUFF_OUT_SIZE
		.align	2
buf_in:		.space  BUFF_IN_SIZE
		
		.align	2
mask:		.word 	1, 1, 1
		.word   1, 1, 1
		.word	1, 1, 1  # macierz 3 na 3
mask_sum:	.word	9

multiplier:  	.float 65536.0

#file_name:	.space 100 	#nazwa pliku 
file_name:	.space	50
output:		.space 50

		.text

.macro printStr (%str)
	.data
str:	.asciiz %str
	.text
	li $v0, 4
	la $a0, str
	syscall
.end_macro
	
.macro printInt (%x)
	li $v0, 1
	add $a0, $zero, %x
	syscall
.end_macro
	
.macro printFixed (%x)
	sra	$a2, %x, 16
	printInt ($a2)
	printStr (".")
	sll	$a2, %x, 16
	srl	$a2, $a2, 16
	printInt ($a2)
.end_macro

.macro int_to_fixed (%source)
 	sll	 %source, %source, 16
.end_macro

.macro fixed_to_int (%source)
    	sra 	%source, %source, 16
.end_macro

.macro fixed_mul (%dest, %first, %second)
    # HI: | significant | LO: | fraction |, do mult = (HI << 16) | (LO >> 16)
     	multu 	%first, %second
    	mflo	%dest
    	srl	%dest, %dest, 16    # 16 bits for fraction
    	mfhi 	$v0
    	sll 	$v0, $v0, 16        # 16 bits for significant
    	or 	%dest, %dest, $v0
.end_macro

.macro fixed_div (%dest, %first, %second)
    	sll 	%dest, %first, 8
    	addu 	$v0, $zero, %second
    	sra 	$v0, $v0, 8
    	div 	%dest, $v0
    	mflo 	%dest
.end_macro

.macro delete_endl(%x)
	la	$t0, %x
find_end:			#szukanie konca nazwy pliku
	lb	$t1, ($t0)
	beqz	$t1, end_of_finding_end
	addiu	$t0,$t0, 1
	b	find_end
	
end_of_finding_end:		# usunięcie znaku \n (zastąpienie go '\0')
	subiu	$t0,$t0,1
	sb	$zero, ($t0)
.end_macro

main:
	printStr("podaj wspolczynniki filtru \n")
	li	$t3, 0 		# zliczanie ile współczynników już podano
	li	$t1, 0  	# mask sum	
	la	$t0, mask  	# iterowanie po tablicy

mask_insert:
	li $v0, 6
    	syscall

    	# konwersja float do fixed-point 16:16
    	# fixed = (int)(float * 2^16)
	l.s 	$f2, multiplier #wczytywanie
    	mul.s 	$f0, $f0, $f2
    	cvt.w.s $f0, $f0
    	mfc1    $t2, $f0
	
	sw	$t2, ($t0) 	 # zapisanie wpisanej wartości do 'macierzy' współczynnników
	
	addu 	$t1, $t1, $t2  # dodanie wartości do sumy
	addiu   $t0, $t0,4	 # zwiększamy indeks w tablicy (tablica pól 4 bajtowych)
	addiu   $t3, $t3,1
	blt	$t3, 9 , mask_insert
	
	sw	$t1, mask_sum
	
printFixed($t1) ###############################################33 9*1,5 != 13.32768
insert_file_name:
	printStr("podaj nazwe pliku wejsciowego\n")
	la	$a0, file_name	# wczytywanie ciagu znakow
	li	$a1, 100
	li	$v0, 8
	syscall	

	delete_endl(file_name)

insert_output_file_name:
	printStr("podaj nazwe pliku wyjsciowego\n")

	la	$a0, output	#wczytywanie ciagu znakow
	li	$a1, 100
	li	$v0, 8
	syscall	

delete_endl(output)
load_file:
	la 	$a0, file_name	# otwarcie pliku
	li 	$a1, 0		
	li 	$a2, 0		
	li 	$v0, 13		
	syscall			
		
	move	$s0, $v0	# skopiowanie deskryptora pliku do rejestru s0
	bltz	$s0, error_file_not_open
	
#file_header:	
	move 	$a0, $s0	
	la 	$a1, temp	
	li 	$a2, 2		
	li 	$v0, 14		#  odczytanie 2 pierwszych bajtow (BM)
	syscall			

	la	$t0, temp
is_bmp:	
	lb	$t1, ($t0)
	bne	$t1, 'B', not_bmp
	addiu	$t0, $t0,1
	lb	$t1, ($t0)
	bne	$t1, 'M', not_bmp

#size:
	move 	$a0, $s0	# wczytanie rozmiaru pliku do size	
	la 	$a1, size	
	li 	$a2, 4		
	li 	$v0, 14		
	syscall			
	
#reserved:	
	move	$a0, $s0	# przejscie o 4 bajty od przodu
	la 	$a1, temp	
	li 	$a2, 4		
	li 	$v0, 14		
	syscall			
#offset:	
	move	$a0, $s0	# wczytanie offsetu do off
	la 	$a1, offset	
	li	$a2, 4		
	li 	$v0, 14		
	syscall			
	
#infoheader:
	move	$a0, $s0	# przejscie o 4 bajty od przodu
	la 	$a1, temp	
	li 	$a2, 4		
	li 	$v0, 14		
	syscall			
#width:	
	move	$a0, $s0	# wczytanie szerokości do width
	la	$a1, width	
	li 	$a2, 4		
	li 	$v0, 14		
	syscall			

#height:
	move	$a0, $a0	# wczytanie wysokości do height
	la 	$a1, height	
	li 	$a2, 4		
	li 	$v0, 14		
	syscall			

reload_input_file:
	la 	$a0, ($s0)	
	li 	$v0, 16   	# zamykanie pliku
	syscall			

	la 	$a0, file_name	# ponowne otworzenie pliku
	li 	$a1, 0		
	li 	$a2, 0		
	li 	$v0, 13		
	syscall		
	move	$s0, $v0	# deskryptor pliku wejściowego w s0

open_output_file:
	la 	$a0, output	# otworzenie pliku wyjściowego
	li 	$a1, 1		# flagi otwarcia (nowy plik)
	li 	$a2, 0		
	li 	$v0, 13		
	syscall			
	
	move	$s1, $v0	# deskryptor pliku wyjściowego w s1

copy_header:
	move 	$a0, $s0	# odczyt z pliku wejściowego 
	la 	$a1, buf_in	# wskazanie bufora wczytywania
	lw	$a2, offset	
	li 	$v0, 14		
	syscall		
	la	$a0, ($s1)	# przepsianie nagłówka do pliku out
	la	$a1, buf_in
	lw	$a2, offset
	li	$v0, 15
	syscall

##################################
# $s0 - input descriptor
# $s1 - output descriptor
# $s2 - pixel x_cord
# $s3 - pixel y_cord
# $s4 - usage of output buffer
# $s5 - width of image (pix)
# $s6 - height of image 
# $s7 - lines per read
#################################

	li	$s4, 0
	lw	$s5, width
	lw	$s6, height	

	mulu	$t0, $s5, 3	#bajtów na linijkę
	
	andi	$t1, $s5, 3	#padding
	addu	$t0, $t0, $t1
	
	li	$s7, BUFF_IN_SIZE
	divu	$s7, $s7, $t0 	#linijek które się na raz zmieszczą w bufforze
	
	li 	$s3, 0
y_image_loop:
	li 	$s2, 0		

load_lines:
	beqz	$s3, first_load
	rem	$t1, $s3, $s7
	bnez	$t1, x_image_loop
first_load:	
	mulu	$t0, $s5, 3	#bajtów na linijkę
	andi	$t1, $s5, 3	#padding
	addu	$t0, $t0, $t1

	move 	$a0, $s0	# odczyt z pliku wejściowego 
	la 	$a1, buf_in	# wskazanie bufora wczytywania
	mulu	$a2, $s7, $t0	# wczytaj tyle linijek ile się da	
	li 	$v0, 14		
	syscall
					
x_image_loop:
	li 	$t1, -1
	sw	$zero, red_tmp
	sw	$zero, green_tmp
	sw	$zero, blue_tmp
y_filter_loop:
	li 	$t0, -1	
x_filter_loop:
	addu	$t2, $s2, $t0 #x
	addu	$t3, $s3, $t1 #y

get_pixel:	

check_left:	
	blt	$t2, 0, duplicate_left	 #jeśli x=-1 to powielamy pixel leżący na lewej krawędzi (x=0)
check_right:	
	bge	$t2, $s5, duplicate_right  #jeśli x = width to powielamy pixel leżący na prawej krawędzi (x=width-1)
	move	$t8, $t2
check_bottom:
	blt	$t3, 0, duplicate_bottom #jeśli y=-1 to powielamy pixel leżący na dolnej krawędzi (y=0)
check_top:
	bge	$t3, $s6, duplicate_top	  #jeśli y = height powielamy pixel leżący na górnej krawędzi (y=height -1)
	move 	$t9, $t3
	b 	get_real_pixel
duplicate_left:
	addiu	$t8, $t2, 1
	b	check_bottom
duplicate_right:
	subiu	$t8, $t2, 1
	b	check_bottom		
duplicate_bottom:
	addiu	$t9, $t3, 1
	b	get_real_pixel
duplicate_top:
	subiu	$t9, $t3, 1
	b	get_real_pixel

get_real_pixel:
	andi	$t2, $s5, 3	#padding
	bnez	$t9, y_not_0  
	li	$t2, 0
y_not_0:	
	rem	$t9, $t9, $s7	# for partial loading
	mulu	$t3, $s5, 3 	#3*width
	addu	$t3, $t3, $t2	#3*width+padding
	mulu	$t9, $t9, $t3	#(3*width+padding)*y
	mulu	$t8, $t8, 3
	addu	$t9, $t9, $t8 	#(3*width+padding)*y + 3*x

	lbu 	$t4, buf_in + 0($t9)
	lbu	$t5, buf_in + 1($t9)
	lbu	$t6, buf_in + 2($t9)
	
get_mask:
	addiu	$t8, $t0, 1 	# x numerujemy od -1 dlatego dodajemy 1 by było od 0
	addiu	$t9, $t1, 1 	# analogicznie dla y
	mul	$t9, $t9, 3 	# bo macierz ma szerokość 3
	add	$t9, $t9, $t8	
	sll	$t9, $t9, 2	#  mnożenie razy 4
	lw	$t7, mask($t9)	
	
	lw	$t8, red_tmp
	#int_to_fixed($t8)
	fixed_mul ($t9, $t4, $t7)
	addu	$t8, $t8, $t9
	#fixed_to_int($t8)
	sw	$t8, red_tmp
	
	lw	$t8, green_tmp
	#int_to_fixed($t8)
	fixed_mul	($t9, $t5, $t7)
	addu	$t8, $t8, $t9
	#fixed_to_int($t8)
	sw	$t8, green_tmp
	
	lw	$t8, blue_tmp
	#int_to_fixed($t8)
	fixed_mul	($t9, $t6, $t7)
	addu	$t8, $t8, $t9
	#fixed_to_int($t8)
	sw	$t8, blue_tmp
	
x_filter_loop_end:
	addiu	$t0, $t0, 1
	ble	$t0, 1, x_filter_loop
y_filter_loop_end:
	addiu	$t1, $t1, 1
	ble	$t1, 1, y_filter_loop

	lw	$t8, mask_sum
	lw 	$t4, red_tmp
	#int_to_fixed($t4)
	fixed_div ($t4, $t4, $t8)
	#fixed_to_int($t4)
	lw 	$t5, green_tmp
	#int_to_fixed($t5)
	fixed_div ($t5, $t5, $t8)
	#fixed_to_int($t5)
	lw 	$t6, blue_tmp
	#int_to_fixed($t6)
	fixed_div	($t6, $t6, $t8)
	#fixed_to_int($t6)
save_pix:
	sb	$t4, buf_out + 0($s4)
	sb	$t5, buf_out + 1($s4)
	sb	$t6, buf_out + 2($s4)		
	addiu	$s4, $s4, 3
	
	addiu	$t2, $s2, 1
	blt	$t2, $s5, no_padding
add_padding:
	andi	$t2, $s5, 3	#padding
	li	$t3, 0xFF
	sb	$t3, buf_out + 0($s4)
	sb	$t3, buf_out + 1($s4)
	sb	$t3, buf_out + 2($s4)
	addu	$s4, $s4, $t2 #??????????????????????????????? czemu tak skoro dodaliśmy 3 bajty
no_padding:
	ble	$s4, BUFF_OUT_LIMIT, dont_save
save:
	la	$a0, ($s1)
	la	$a1, buf_out
	la	$a2, ($s4)
	li	$v0, 15
	syscall
	li	$s4, 0	
dont_save:																																																			

x_image_loop_end:
	addiu	$s2, $s2, 1
	blt	$s2, $s5, x_image_loop
y_image_loop_end:
	addiu	$s3, $s3, 1
	blt	$s3, $s6, y_image_loop

filter_done:	
save_remaining_data:			
	la	$a0, ($s1)
	la	$a1, buf_out
	la	$a2, ($s4)
	li	$v0, 15
	syscall
	
close_input_file:
	la 	$a0, ($s0)	
	li 	$v0, 16   	# zamknięcie pliku wejsciowego
	syscall
close_output_file:
	la 	$a0, ($s1)	
	li 	$v0, 16   	# zamknięcie pliku wyjsciowego
	syscall		
	b	end				
		
error_file_not_open:
	printStr("Blad odczytu pliku zrodlowego\n")
	b 	end
not_bmp:
	printStr("Zly format pliku\n")
	b 	end	
end:
	li	$v0, 10
	syscall

