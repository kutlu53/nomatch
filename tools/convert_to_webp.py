#!/usr/bin/env python3
"""
PNG görsellerini WebP formatına dönüştüren script
Kullanım: python convert_to_webp.py
"""

from PIL import Image
import os
import sys

def convert_png_to_webp(input_folder, output_folder=None, quality=85):
    """
    PNG dosyalarını WebP formatına çevirir
    
    Args:
        input_folder: PNG dosyalarının bulunduğu klasör
        output_folder: WebP dosyalarının kaydedileceği klasör (None ise aynı klasör)
        quality: WebP kalite ayarı (0-100, varsayılan 85)
    """
    
    if not os.path.exists(input_folder):
        print(f"❌ Hata: '{input_folder}' klasörü bulunamadı!")
        return
    
    # Output folder belirtilmemişse input folder kullan
    if output_folder is None:
        output_folder = input_folder
    
    # Output klasörünü oluştur
    if not os.path.exists(output_folder):
        os.makedirs(output_folder)
        print(f"📁 '{output_folder}' klasörü oluşturuldu")
    
    # PNG dosyalarını bul
    png_files = [f for f in os.listdir(input_folder) if f.lower().endswith('.png')]
    
    if not png_files:
        print(f"⚠️  '{input_folder}' klasöründe PNG dosyası bulunamadı!")
        return
    
    print(f"\n🔄 {len(png_files)} adet PNG dosyası bulundu. Dönüştürme başlıyor...\n")
    
    success_count = 0
    error_count = 0
    
    for filename in png_files:
        input_path = os.path.join(input_folder, filename)
        output_filename = filename.rsplit('.', 1)[0] + '.webp'
        output_path = os.path.join(output_folder, output_filename)
        
        try:
            # PNG'yi aç ve WebP olarak kaydet
            image = Image.open(input_path)
            
            # RGBA modundaysa (şeffaf PNG) şeffaflığı koru
            if image.mode in ('RGBA', 'LA'):
                image.save(output_path, 'webp', quality=quality, lossless=False)
            else:
                image.save(output_path, 'webp', quality=quality)
            
            # Dosya boyutlarını göster
            input_size = os.path.getsize(input_path) / 1024  # KB
            output_size = os.path.getsize(output_path) / 1024  # KB
            reduction = ((input_size - output_size) / input_size) * 100
            
            print(f"✅ {filename:30} -> {output_filename:30} ({input_size:6.1f}KB -> {output_size:6.1f}KB, %{reduction:.1f} azalma)")
            success_count += 1
            
        except Exception as e:
            print(f"❌ {filename:30} -> HATA: {e}")
            error_count += 1
    
    print(f"\n{'='*80}")
    print(f"✅ Başarılı: {success_count} dosya")
    if error_count > 0:
        print(f"❌ Hatalı: {error_count} dosya")
    print(f"{'='*80}\n")


def main():
    print("="*80)
    print("PNG -> WebP Dönüştürücü")
    print("="*80)
    
    # Kullanıcıdan input klasörünü al
    print("\nPNG dosyalarının bulunduğu klasör yolunu girin:")
    print("(Örnek: yeni_sorular veya C:\\Users\\Desktop\\images)")
    input_folder = input("Klasör yolu: ").strip().strip('"')
    
    if not input_folder:
        print("❌ Klasör yolu boş olamaz!")
        return
    
    # Kullanıcıdan output klasörünü al
    print("\nWebP dosyalarının kaydedileceği klasör:")
    print("(Boş bırakırsanız aynı klasöre kaydedilir)")
    print("(Örnek: assets/questions)")
    output_folder = input("Output klasörü (opsiyonel): ").strip().strip('"')
    
    if not output_folder:
        output_folder = None
    
    # Kalite ayarı
    print("\nKalite ayarı (0-100, varsayılan 85):")
    print("(85-90 arası önerilir, yüksek kalite ve iyi sıkıştırma dengesi)")
    quality_input = input("Kalite (Enter=85): ").strip()
    
    try:
        quality = int(quality_input) if quality_input else 85
        if quality < 0 or quality > 100:
            print("⚠️  Kalite 0-100 arasında olmalı, 85 kullanılıyor")
            quality = 85
    except ValueError:
        print("⚠️  Geçersiz kalite değeri, 85 kullanılıyor")
        quality = 85
    
    # Dönüştürmeyi başlat
    convert_png_to_webp(input_folder, output_folder, quality)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  İşlem kullanıcı tarafından iptal edildi")
        sys.exit(0)
