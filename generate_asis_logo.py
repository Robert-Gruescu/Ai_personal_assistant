from PIL import Image, ImageDraw, ImageFont
import os

def create_asis_logo(size, output_path):
    """Create ASIS logo with blue background and white stylized text"""
    
    # Colors
    blue = (63, 81, 181)  # Indigo/Blue
    white = (255, 255, 255)
    light_blue = (100, 130, 220)
    
    # Create image with blue background
    img = Image.new('RGBA', (size, size), blue)
    draw = ImageDraw.Draw(img)
    
    # Add a gradient-like effect with circles
    center = size // 2
    
    # Outer glow circle
    for i in range(3):
        offset = size // 8 - i * 5
        draw.ellipse(
            [offset, offset, size - offset, size - offset],
            outline=light_blue,
            width=2
        )
    
    # Inner circle (lighter blue)
    inner_margin = size // 6
    draw.ellipse(
        [inner_margin, inner_margin, size - inner_margin, size - inner_margin],
        fill=(83, 101, 201)
    )
    
    # Try to use a nice font, fallback to default
    font_size = size // 3
    try:
        # Try common fonts
        font_paths = [
            "C:/Windows/Fonts/arialbd.ttf",
            "C:/Windows/Fonts/segoeui.ttf",
            "C:/Windows/Fonts/calibrib.ttf",
            "C:/Windows/Fonts/arial.ttf",
        ]
        font = None
        for fp in font_paths:
            if os.path.exists(fp):
                font = ImageFont.truetype(fp, font_size)
                break
        if font is None:
            font = ImageFont.load_default()
    except:
        font = ImageFont.load_default()
    
    # Draw "ASIS" text
    text = "ASIS"
    
    # Get text bounding box
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    # Center the text
    x = (size - text_width) // 2
    y = (size - text_height) // 2 - size // 20
    
    # Draw shadow
    shadow_offset = max(1, size // 100)
    draw.text((x + shadow_offset, y + shadow_offset), text, font=font, fill=(40, 50, 120))
    
    # Draw main text
    draw.text((x, y), text, font=font, fill=white)
    
    # Add a microphone icon hint (small arc at bottom)
    mic_y = y + text_height + size // 15
    mic_size = size // 8
    draw.arc(
        [center - mic_size, mic_y, center + mic_size, mic_y + mic_size],
        0, 180,
        fill=white,
        width=max(2, size // 50)
    )
    
    # Add small dot for microphone
    dot_radius = size // 30
    draw.ellipse(
        [center - dot_radius, mic_y + mic_size // 4, center + dot_radius, mic_y + mic_size // 4 + dot_radius * 2],
        fill=white
    )
    
    # Save
    img.save(output_path, 'PNG')
    print(f"✅ Created: {output_path}")

def main():
    base_path = r"c:\Users\robij\OneDrive\Desktop\Game Changer\ai_personal_assistant\android\app\src\main\res"
    
    # Android mipmap sizes
    sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    
    for folder, size in sizes.items():
        folder_path = os.path.join(base_path, folder)
        if not os.path.exists(folder_path):
            os.makedirs(folder_path)
        
        # Create launcher icon
        output = os.path.join(folder_path, "ic_launcher.png")
        create_asis_logo(size, output)
    
    # Also create for assets folder (for Flutter use)
    assets_path = r"c:\Users\robij\OneDrive\Desktop\Game Changer\ai_personal_assistant\assets\icon"
    if not os.path.exists(assets_path):
        os.makedirs(assets_path)
    
    create_asis_logo(512, os.path.join(assets_path, "asis_logo.png"))
    create_asis_logo(1024, os.path.join(assets_path, "asis_logo_large.png"))
    
    print("\n🎉 All ASIS logos generated successfully!")
    print("Now run: flutter clean && flutter build apk --release")

if __name__ == "__main__":
    main()
