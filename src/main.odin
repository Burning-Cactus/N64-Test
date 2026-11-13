package main

import "base:intrinsics"
import "base:builtin"

Vec2ui :: [2]u32
Vec2i :: [2]i32
Vec2 :: [2]f32

// ctrl flags, copied from Libdragon
VI_DeditherFilter_Enable :: 1<<16
VI_PixelAdvance_Default :: 0b11 << 12
VI_PixelAdvance_BBPlayer :: 1 << 12
VI_AAMode_None :: 0b11 << 8
VI_AAMode_Resample :: 0b10 << 8
VI_AAMode_ResampleFetchNeeded :: 1 << 8
VI_AAMode_ResampleFetchAlways :: 0 << 8
VI_Ctrl_Serrate :: 1 << 6
VI_Divot_Enable :: 1 << 4
VI_Gamma_Enable :: 1 << 3
VI_GammaDither_Enable :: 1 << 2
VI_CtrlType :: 0b11
VI_CtrlType_32bpp :: 0b11 // Bytes per pixel
VI_CtrlType_16bpp :: 0b10
VI_CtrlType_Blank :: 0


VI_Regs :: struct {
	ctrl: u32, // 17 bits. Video configuration, Make this a bit set later
	origin: u32, // 24 bits. Base framebuffer address. Must be a multiple of 8, and bits 2-0 must be 0.
	h_width: u32, // Width in pixels of the frame buffer. Common values are 320 and 640, the max being 4095.
	v_intr: u32, // Vertical interrupt line. libultra and libdragon set this to 2.
	v_current_line: u32, // Current half-line
	burst_timing: u32, // No idea
	v_total: u32, // One less than total visible and non-visible lines
	h_total: u32, // One less than total length of a scanline in 1/4 pixel units
	h_total_leap: u32, // Alternate scanline length?
	h_video: u32, // Start/end of active video image in screen pixels
	v_video: u32, // Start/end of active video image in screen half-lines
	v_burst: u32, //?
	x_scale: u32, // Subpixel offset?
	y_scale: u32, // Subpixel offset?
	test_addr: u32,
	staged_data: u32,
}
VI_REGS :: (^VI_Regs)(uintptr(0xA4400000))


RESOLUTION :: Vec2ui{320, 240}
buffer_addrs: [2]uintptr


// Entry point for the game.
@(export)
@(link_name="_start")
@(link_section=".boot")
_start :: proc() {
	buffer_addrs[0] = 0x0010_0000
	buffer_addrs[1] = buffer_addrs[0] + uintptr(RESOLUTION.x * RESOLUTION.y * size_of(u16))

	VI_REGS^.ctrl = VI_CtrlType_16bpp | VI_AAMode_Resample | VI_PixelAdvance_Default | VI_Gamma_Enable | VI_GammaDither_Enable
	VI_REGS^.ctrl = VI_CtrlType_16bpp
	VI_REGS^.origin = u32(buffer_addrs[0])
	VI_REGS^.h_width = RESOLUTION.x
	VI_REGS^.v_intr = 0x200
	VI_REGS^.v_current_line = 0
	VI_REGS^.burst_timing = 0x3E5_2239
	VI_REGS^.v_total = 0x20D
	VI_REGS^.h_total = 0xC15
	VI_REGS^.h_total_leap = 0x0C15_0C15
	VI_REGS^.h_video = 0x006C02EC
	VI_REGS^.v_video = 0x002501FF
	VI_REGS^.v_burst = 0x000E0204 // Typical values apparently
	VI_REGS^.x_scale = 0x200
	VI_REGS^.y_scale = 0x0100_0400


	// Memory barrier
	_ = intrinsics.volatile_load(VI_REGS)
	// Memory barrier prevents compiler optimizations on ASM. If I need it, consider using volatile operations instead.


	// This'll need a double buffer later to not strain the eyes, probably.
	x_offset: i32 = 0

	on_second_buffer: bool
	for {
		if VI_REGS^.v_current_line == VI_REGS^.v_intr {
			on_second_buffer = !on_second_buffer
			buf_idx := 1 if on_second_buffer else 0
			buf_addr := buffer_addrs[buf_idx]
			x_offset += 1

			draw_voronoi_grid(buf_addr, x_offset)
// 			buffer_location := cast([^]u16) (buf_addr + 0xA000_0000)
// 			for i: i32 = 0; i < i32(RESOLUTION.x * RESOLUTION.y); i += 1  {
// 				x := i %% i32(RESOLUTION.x) + x_offset
// 				y := i / i32(RESOLUTION.x)
//
// 				is_red := false
// 				is_red ~= (x %% 32) < 16
// 				is_red ~= (y %% 32) < 16
// 				if is_red {
// 					buffer_location[i] = 0xF801
// 				} else {
// 					buffer_location[i] = 0x0183
// 				}
// 			}
			VI_REGS^.origin = u32(buf_addr)
		}
	}
}

// Currently runs at 0.5 FPS on the CPU
draw_voronoi_grid :: proc(buf_addr: uintptr, x_offset: i32) {
	colors := [8]u16 {
		0b01111_01111_01111_1,
		0xF801,
		0x0183,
		0b00100_10011_10011_1,
		0b01000_00011_01001_1,
		0xBBBA,
		0b11101_01111_10011_1,
		0b00011_00011_00011_1,
	}

	buffer_location := cast([^]u16) (buf_addr + 0xA000_0000)
	cell_size :: Vec2i{32, 32}
	res :: Vec2i{i32(RESOLUTION.x), i32(RESOLUTION.y)}
	for x: i32 = 0; x < res.x; x += 1 {
		for y: i32 = 0; y < res.y; y += 1 {
			// Find current cell
			world_pos := Vec2i{(x - x_offset), y}
			cell := Vec2i{world_pos.x / cell_size.x, world_pos.y / cell_size.y}

			min_distance_sqr: i32 = 0x7FFF_FFFF
			closest_cell: Vec2i
			is_point: bool
			for i: i32 = -1; i <= 1; i += 1 {
				for j: i32 = -1; j <= 1; j += 1 {
					current_cell := cell + {i, j}
					// Calculate pseudorandom point in cell
					voronoi_x := dot_product_i(4 * (current_cell.x + 19), 7 * (current_cell.y + 4))
					voronoi_x ~= ((current_cell.x * current_cell.y) << 5)
					voronoi_x %%= cell_size.x
					voronoi_y := dot_product_i(8 * (current_cell.x + 2), current_cell.y + 13)
					voronoi_y ~= ((current_cell.x * current_cell.y) << 7)
					voronoi_y %%= cell_size.y
					actual_pos := Vec2i{current_cell.x * cell_size.x + voronoi_x, current_cell.y * cell_size.y + voronoi_y}
					if world_pos.x == actual_pos.x && world_pos.y == actual_pos.y {
						is_point = true
					}
					x_length := actual_pos.x - world_pos.x
					y_length := actual_pos.y - world_pos.y
					dist_sqr := x_length * x_length + y_length * y_length
					if dist_sqr < min_distance_sqr {
						min_distance_sqr = dist_sqr
						closest_cell = current_cell
					}
				}
			}

			is_red := (cell.x + cell.y) %% 2 == 0
			pixel_idx := y * res.x + x
			if is_point {
				buffer_location[pixel_idx] = 0
			} else {
				col_idx := closest_cell.x + closest_cell.y * (res.x / cell_size.x)
				col_idx %%= len(colors)
				buffer_location[pixel_idx] = colors[col_idx]
			}
		}
	}
}

// Use these for a dirty random implementation
dot_product_i :: proc(a: Vec2i, b: Vec2i) -> i32 {
	return a.x * b.x + a.y * b.y
}

dot_product_f :: proc(a: Vec2, b: Vec2) -> f32 {
	return a.x * b.x + a.y * b.y
}

@(export)
@(link_section=".text")
memset :: proc "c" (a: rawptr, c: builtin.i32, n: builtin.u32) -> rawptr {
	character := u8(c)
	mem_array := cast([^]u8) a
	for i: u32 = 0; i < n; i += 1 {
		mem_array[i] = character
	}
	return a
}

@(export)
@(link_section=".text")
memmove :: proc "c" (dest: rawptr, src: rawptr, n: builtin.u32) -> rawptr {
	dest_p := cast([^]u8) dest
	src_p := cast([^]u8) src
	size := i32(n)
	if src > dest {
		for i: i32 = size - 1; i >= 0; i -= 1 {
			dest_p[i] = src_p[i]
		}
	} else {
		for i: i32 = 0; i < size; i += 1 {
			dest_p[i] = src_p[i]
		}
	}
	return dest
}
