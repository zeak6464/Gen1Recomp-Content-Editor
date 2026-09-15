import io
import pytest
from PIL import Image, ImageDraw
from mod_scanner.core.image_scanner import (
    normalize_image_for_hashing,
    compute_image_hash,
    calculate_hamming_distance,
    generate_diff_preview,
)


def create_sample_sprite(color=(200, 50, 50), shape="circle") -> Image.Image:
    img = Image.new("RGBA", (56, 56), (0, 0, 0, 0))  # Transparent background
    draw = ImageDraw.Draw(img)
    if shape == "circle":
        draw.ellipse((8, 8, 48, 48), fill=color, outline=(0, 0, 0, 255))
        draw.rectangle((20, 20, 26, 26), fill=(255, 255, 255, 255))  # eye
    elif shape == "square":
        draw.rectangle((10, 10, 46, 46), fill=color, outline=(0, 0, 0, 255))
    return img


def test_alpha_normalization_consistency():
    # An RGBA sprite with transparent background vs same sprite composited onto white
    sprite = create_sample_sprite()
    norm1 = normalize_image_for_hashing(sprite)

    # Pre-composited over white
    white_bg = Image.new("RGBA", (56, 56), (255, 255, 255, 255))
    white_bg.alpha_composite(sprite)
    norm2 = normalize_image_for_hashing(white_bg)

    # Both must result in identical grayscale images
    assert list(norm1.getdata()) == list(norm2.getdata())


def test_recolor_low_hamming_distance():
    # Red sprite vs Blue recolor of exact same geometry
    red_sprite = create_sample_sprite(color=(220, 30, 30))
    blue_recolor = create_sample_sprite(color=(30, 30, 220))

    hash_red = compute_image_hash(red_sprite, hash_size=16)
    hash_blue = compute_image_hash(blue_recolor, hash_size=16)

    dist = calculate_hamming_distance(hash_red, hash_blue)
    # Direct recolor should produce very low Hamming distance (within rip/recolor threshold <= 16)
    assert dist <= 16


def test_distinct_shape_high_hamming_distance():
    # Circle sprite vs Square sprite
    circle = create_sample_sprite(shape="circle")
    square = create_sample_sprite(shape="square")

    hash_circle = compute_image_hash(circle, hash_size=16)
    hash_square = compute_image_hash(square, hash_size=16)

    dist = calculate_hamming_distance(hash_circle, hash_square)
    # Different shapes must have high distance (> 28)
    assert dist > 28


def test_diff_preview_generation():
    img1 = create_sample_sprite(shape="circle")
    img2 = create_sample_sprite(shape="square")

    canvas = generate_diff_preview(img1, img2, panel_size=64, upscale_factor=2)
    assert canvas.mode == "RGB"
    assert canvas.width > 64 * 3
    assert canvas.height > 64
