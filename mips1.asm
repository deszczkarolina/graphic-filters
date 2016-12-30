.eqv		BUFF_OUT_SIZE 	512
.eqv		BUFF_IN_SIZE	0x300000	
	
		.globl main
		.data

size:		.word 0	# rozmiar pliku bmp w pixelach
width:		.word 0 # szerokosc pliku bmp w pixelach
height:		.word 0	# wysokosc pliku bmp w pixelach
off:		.word 0	# offset - początek tablicy pikseli
temp:		.word 0	# bufor wczytywania
beginning:	.word 0	# adres poczatku linijki
bpp:		.word 0

red_tmp:	.word 0
green_tmp:	.word 0
blue_tmp:	.word 0
alpha_tmp:	.word 0

buf_out:	.space  BUFF_OUT_SIZE
buf:		.space  BUFF_IN_SIZE
		
		.align	2

mask:		.word	1, 1, 1
		.word   1, 1, 1
		.word	1, 1, 1  # macierz 3 na 3
mask_sum:	.word	9

#file_name:	.space 100 	#nazwa pliku 
file_name:	.asciiz	"0.bmp" 
hello:		.asciiz	"filtr dolnoprzepustowy - podaj nazwe pliku\n"
mask_values:	.asciiz "podaj wspólczynniki filtru \n"
opened:		.asciiz "Plik zostal otwarty\n"
input:		.asciiz	"in.bmp"
output:		.asciiz "out.bmp"
load_error:	.asciiz "Blad odczytu pliku zrodlowego\n"
wrong_file:	.asciiz "zly format pliku \n"
err2:		.asciiz "Blad tworzenia pliku docelowego\n"		
		.text
	
.macro choose_pix (%x, %y, %dest) 
	blt	%x, 0, duplicate_side	 #jeśli x=-1 to powielamy pixel leżący na bocznej krawędzi (x=0)
	move	$t8, %x
check_y:
	blt	%y, 0, duplicate_bottom	 #jeśli y=-1 to powielamy pixel leżący na dolnej krawędzi (y=0)
	move 	$t9, %y
	b	correct_arguments
duplicate_side:
	addiu	$t8, %x, 1
	b	check_y	
duplicate_bottom:
	addiu	$t9, %y, 1
correct_arguments:
	lw	$t7, width
	mul	$t8, $t8, 3	  #x - mnożenie razy 3 (pixel ma 3 bajty)
	mul	$t9, $t9, 3	  #y - mnożenie razy 3
	mul	$t9, $t9, $t7	  # mnożenie przez szerokość
	add	$t9, $t9, $t8	  # adres pixelu = x*3 + y*szerokość*3
	ulw	%dest, buf($t9)	  # wartość pixela w dest
	srl	%dest, %dest, 8
	#li	%dest, 0xFFAABBFF
.end_macro	

.macro store_pix(%pix, %x)

	sll	%pix, %pix, 8
	ulw	$t9, buf_out($s4)
	andi	$t9, 0x000000FF
	or	%pix, %pix, $t9
	usw	%pix, buf_out($s4)
	
#	sb	%pix, buf_out + 0($s4)
#	srl	%pix, %pix, 8
#	sb	%pix, buf_out + 1($s4)
#	srl	%pix, %pix, 8
#	sb	%pix, buf_out + 2($s4)
 	
	addiu	$s4, $s4, 3 	  # 1 pixel to 3 bajty
	bne	%x, $s5, save_buf_to_file 
	
add_padding:
	andi	$t3, $s5, 3
	add	$s4, $s4, $t3
	# TU COŚ JEST ŹLE !!!!!!
	addiu	$s4, $s4, -5
	
save_buf_to_file:
	blt	$s4, BUFF_OUT_SIZE, dont_save
	la	$a0, ($s1)
	la	$a1, buf_out
	la	$a2, ($s4)
	li	$v0, 15
	syscall
	li	$s4, 0
dont_save:	

.end_macro

.macro matrix_index(%x, %y, %dest )
	
	
	addiu	$t8, %x, 1 	# x numerujemy od -1 dlatego dodajemy 1 by było od 0
	addiu	$t9, %y, 1 	# analogicznie dla y
	sll	$t8, $t8, 2	  #x - mnożenie razy 4
	sll	$t9, $t9, 2	  #y - mnożenie razy 4
	mul	$t9, $t9, 3 	# bo macierz ma szerokość 3
	add	$t9, $t9, $t8	#'indeks' w tablico-macierzy
	lw	%dest, mask($t9)	
.end_macro

main:
	la	 $a0, hello	# wczytanie adresu stringa hello do rejestru a0
	li 	 $v0, 4	# ustawienie syscall na wypisywanie stringa
	syscall
	#TFIXME - REMOV
	b	 load_file
	la	 $a0, mask_values	# wczytanie adresu stringa mask_value do rejestru a0
	li 	 $v0, 4	# ustawienie syscall na wypisywanie stringa
	syscall
	
	li	$t0, 0 # indeksowanie po masce
	li	$t1, 0 # mask sum

mask_insert:
	li	$v0, 5
	syscall	
	
	move	$t2, $v0
	add	$t1, $t1, $t2
	addiu   $t0, $t0,1
	blt	$t0, 9 , mask_insert
	
	sw	$t1, mask_sum
	
#	lw	$a0, mask_sum
#	li	$v0, 1
#	syscall
	
	
#	b	load_file
	#########################################################	
insert_file_name:
	la	$a0, file_name	#wczytywanie ciagu znakow
	li	$a1, 100
	li	$v0, 8
	syscall	

	la	$t0, file_name

							
find_end:		#szukanie konca nazwy pliku
	lb	$t1, ($t0)
	beqz	$t1, end_of_finding_end
	addiu	$t0, $t0, 1
	b	find_end
	
end_of_finding_end:   # usunięcie znaku \n (zastąpienie go '\0')
	subiu	$t0, $t0, 1
	sb	$zero, ($t0)
	
	
load_file:
	la 	$a0, file_name	# wczytanie nazwy pliku do otwarcia
	li 	$a1, 0		# flagi otwarcia
	li 	$a2, 0		# tryb otwarcia
	li 	$v0, 13		# ustawienie syscall na otwieranie pliku
	syscall			# otwarcie pliku, zostawienie w $v0 jego deskryptora
	
	move	$s0, $v0	# skopiowanie deskryptora pliku do rejestru s0
	bltz	$t0, error_file_not_open
	
#file_header:	
	move 	$a0, $s0	# przekopiowanie deskryptora do a0
	la 	$a1, temp	# wskazanie bufora wczytywania
	li 	$a2, 2		# ustawienie odczytu 2 pierwszych bajtow (BM)
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# odczytanie z pliku

	la	$t0, temp
is_bmp:	
	lb	$t1, ($t0)
	bne	$t1, 'B', not_bmp
	addiu	$t0, $t0,1
	lb	$t1, ($t0)
	bne	$t1, 'M', not_bmp

#size:
	move 	$a0, $s0	# przekopiowanie deskryptora do a0
	la 	$a1, size	# wskazanie zmiennej do przechowywania wczytanych danych
	li 	$a2, 4		# ustawienie odczytu 4 bajtow
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# wczytanie rozmiaru pliku do size	
	
#reserved:	
	move	$a0, $s0	# przekopiowanie deskryptora do a0
	la 	$a1, temp	# wskazanie bufora wczytywania
	li 	$a2, 4		# ustawienie odczytu 4 bajtow zarezerwowanych
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# przejscie o 4 bajty od przodu
#offset:	
	move	$a0, $s0	# przekopiowanie deskryptora do a0
	la 	$a1, off	# wskazanie zmiennej do przechowywania offsetu
	li	$a2, 4		# ustawienie odczytu 4 bajtow offsetu
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# wczytanie offsetu do off
	
#infoheader:
	move	$a0, $s0	# przekopiowanie deskryptora do a0
	la 	$a1, temp	# wskazanie bufora wczytywania
	li 	$a2, 4		# ustawienie odczytu 4 bajtow - wielkosci naglowka informacyjnego
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# przejscie o 4 bajty od przodu
#width:	
	move	$a0, $s0	# przekopiowanie deskryptora do a0
	la	$a1, width	# wskazanie zmiennej do przechowywania szerokosci
	li 	$a2, 4		# ustawienie odczytu 4 bajtow - szerokosci
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# wczytanie szerokosci bitmapy

#height:
	move	$a0, $a0	# przekopiowanie deskryptora do a0
	la 	$a1, height	# wskazanie zmiennej do przechowywania wysokosci
	li 	$a2, 4		# ustawienie odczytu 4 bajtow - wysokosci
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# wczytanie wysokosci bitmapy

#planes:
	move	$a0, $a0	# przekopiowanie deskryptora do a0
	la 	$a1, temp	# wskazanie zmiennej do przechowywania wysokosci
	li 	$a2, 2		# ustawienie odczytu 4 bajtow - wysokosci
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# wczytanie wysokosci bitmapy

#BPP:
	move	$a0, $a0	# przekopiowanie deskryptora do a0
	la 	$a1, bpp	# wskazanie zmiennej do przechowywania wysokosci
	li 	$a2, 2		# ustawienie odczytu 4 bajtow - wysokosci
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall			# wczytanie wysokosci bitmapy
	
			
reload_input_file:
	la 	$a0, ($s0)	# deskryptor pliku do a0
	li 	$v0, 16   	# ustawienie syscall na zamykanie pliku
	syscall			

	la 	$a0, file_name	# wczytanie nazwy pliku do otwarcia
	li 	$a1, 0		# flaga otwarcia
	li 	$a2, 0		# tryb otwarcia
	li 	$v0, 13		# ustawienie syscall na otwieranie pliku
	syscall			# otwarcie pliku, zostawienie w $v0 jego deskryptora
	move	$s0, $v0

open_output_file:
	la 	$a0, output	# wczytanie nazwy pliku do otwarcia
	li 	$a1, 1		# flagi otwarcia (nowy plik)
	li 	$a2, 0		# tryb otwarcia
	li 	$v0, 13		# ustawienie syscall na otwieranie pliku
	syscall			# otwarcie pliku, zostawienie w $v0 jego deskryptora
	
	move	$s1, $v0	#deskryptor pliku wyjściowego w s1

copy_header:
	move 	$a0, $s0	# przekopiowanie deskryptora do a0
	la 	$a1, buf	# wskazanie bufora wczytywania
	lw	$a2, off	
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall		

	la	$a0, ($s1)	#przepsianie nagłówka do pliku out
	la	$a1, buf
	lw	$a2, off
	li	$v0, 15
	syscall
	
##################################
# $s0 - input escriptor
# $s1 - output descriptor
# $s2 - pixel x_cord
# $s3 - pixel y_cord
# $s4 - usage of output buffer
# $s5 - width of image
# $s6 - height of image
# $s7 - lines per read
#################################
magic:
	li	$s4, 0 		# zlicza ile pikseli jest zapisanych do bufora out
 	lw 	$s5, width	# zaladowanie szerokosci do rejestru t5
 	lw 	$s6, height	# zaladowanie wysokości do rejestru t6
	
	li	$s7, BUFF_IN_SIZE
	#sra	$s7, $s7, 2	# podziel przez 4 - 4 bajty na pixel
	#divu	$s7, $s7, $s6	# tyle linijek moge wczytać na raz
	
	#ble	$s7, $s6, full_buff 
	#move	$s7, $s6
full_buff:															
	move 	$a0, $s0  	# przekopiowanie deskryptora do a0
	la 	$a1, buf	# wskazanie bufora wczytywania
	mul	$a2, $s5, $s7	#wczytanie $s7 linijek 
	li 	$v0, 14		# ustawienie syscall na odczyt z pliku
	syscall
	
	li	$s3, 0  	# bieżące położenie w obrazku  - y
row_loop:
  	bgt 	$s3, $s6, row_loop_end
  	li	$s2, 0
  	
column_loop:
	# has x_coord reached width
 	bgt	$s2, $s5, column_loop_end 	
	
	li	$t0, -1 	#iterowanie po x wewnątrz maski
 	sw	$zero, red_tmp
 	sw	$zero, green_tmp
 	sw	$zero, blue_tmp	 	 	 		 	 	 	
splot_loop_x:
	bgt	$t0, 1, splot_loop_end # jeśli x>1
 	li	$t1, -1 	#iterowanie po y w masce 
splot_loop_y:
	bgt	$t1, 1, end_loop_y
	add	$t2, $t0, $s2 
	add	$t3, $t1, $s3 
###########################################
# $t0 - mask x_coord
# $t1 - mask y_coord
# $t2 - pixel
# $t3 - mask
###########################################	
	choose_pix ($t2, $t3, $t2)
	matrix_index ($t0, $t1, $t3)
	andi	$t4, $t2, 0x000000FF	#choose red color
	mul	$t4, $t4, $t3		# pixel * mask
	lw	$t5, red_tmp
	addu	$t5, $t5, $t4
	sw	$t5, red_tmp			

	andi	$t4, $t2, 0x0000FF00	#choose grren color
	mul	$t4, $t4, $t3		# pixel * mask
	lw	$t5, green_tmp
	addu	$t5, $t5, $t4
	sw	$t5, green_tmp			

	andi	$t4, $t2, 0x00FF0000	#choose blue color
	mul	$t4, $t4, $t3		# pixel * mask
	lw	$t5, blue_tmp
	addu	$t5, $t5, $t4
	sw	$t5, blue_tmp
												
	addiu	$t1, $t1, 1	
	b	splot_loop_y

end_loop_y:
	addiu	$t0, $t0, 1
	b	splot_loop_x	
splot_loop_end:	
	xor	$t2, $t2, $t2
	lw	$t4, mask_sum
	lw	$t3, red_tmp
	divu 	$t3, $t3, $t4 
	andi	$t3, $t3, 0x000000FF
	or	$t2, $t2, $t3
	
	lw	$t3, green_tmp
	divu	$t3, $t3, $t4 
	andi	$t3, $t3, 0x0000FF00
	or	$t2, $t2, $t3
	
	
	
	lw	$t3, blue_tmp
	divu	$t3, $t3, $t4 
	andi	$t3, $t3, 0x00FF0000
	or	$t2, $t2, $t3
	
	store_pix($t2, $s2)
	
	addiu	$s2, $s2, 1 # increment x
	b	column_loop
column_loop_end:
	#read new lines if needed
	#probably copy the last one at the beggining
	#HERE
	#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	# sth with $s7, $s5
	
	addiu	$s3, $s3, 1
	b	row_loop
row_loop_end:

save_rest_buf_to_file:
	la	$a0, ($s1)
	la	$a1, buf_out
	la	$a2, ($s4)
	li	$v0, 15
	syscall

close_input_file:
	la 	$a0, ($s0)	# deskryptor pliku do a0
	li 	$v0, 16   	# ustawienie syscall na zamykanie pliku
	syscall
close_output_file:
	la 	$a0, ($s1)	# deskryptor pliku do a0
	li 	$v0, 16   	# ustawienie syscall na zamykanie pliku
	syscall		
	b	end
error_file_not_open:
	la	$a0, load_error
	li	$v0, 4
	syscall
	b 	end
not_bmp:
	la	$a0, wrong_file	  # not bmp file
	li	$v0, 4
	syscall
	b 	end	
end:
	li	$v0, 10
	syscall
