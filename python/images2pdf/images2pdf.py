import sys
import argparse
from pathlib import Path
from PIL import Image, ImageOps
import pillow_heif

def create_pdf_from_photos(folder_path):
    # Resolve o caminho para obter o nome absoluto e garantir que funciona com caminhos relativos (ex: '.')
    folder = Path(folder_path).resolve()
    
    if not folder.is_dir():
        print(f"Erro: O caminho '{folder_path}' não é uma pasta válida.")
        sys.exit(1)

    # Regista o suporte HEIC/HEIF no motor do Pillow
    pillow_heif.register_heif_opener()

    # Extensões suportadas
    valid_extensions = {'.heic', '.jpeg', '.jpg', '.png'}
    
    # Lista os ficheiros válidos e ordena alfabeticamente
    image_files = sorted([
        f for f in folder.iterdir()
        if f.suffix.lower() in valid_extensions and f.is_file()
    ])

    if not image_files:
        print("Nenhuma imagem suportada (HEIC, JPEG, PNG) encontrada na pasta.")
        sys.exit(1)

    # Configurações do "canvas" A4 a 150 DPI (bom equilíbrio entre qualidade da foto e peso do PDF)
    A4_W, A4_H = 1240, 1754
    pdf_pages = []

    for img_path in image_files:
        try:
            img = Image.open(img_path)
            
            # Vital para fotos mobile: roda a imagem com base na tag de orientação do EXIF
            img = ImageOps.exif_transpose(img)
            
            # O formato PDF não suporta canal alpha (transparência), convertemos para RGB
            if img.mode in ('RGBA', 'P'):
                img = img.convert('RGB')
            
            # Redimensiona mantendo a proporção original para não exceder as margens A4
            img.thumbnail((A4_W, A4_H), Image.Resampling.LANCZOS)
            
            # Cria um fundo branco e calcula as coordenadas para centrar a imagem
            canvas = Image.new('RGB', (A4_W, A4_H), (255, 255, 255))
            offset_x = (A4_W - img.width) // 2
            offset_y = (A4_H - img.height) // 2
            canvas.paste(img, (offset_x, offset_y))
            
            pdf_pages.append(canvas)
            print(f"Processado: {img_path.name}")
            
        except Exception as e:
            print(f"Aviso: Não foi possível processar '{img_path.name}'. Erro: {e}")

    if pdf_pages:
        # Guarda o ficheiro PDF na mesma diretoria onde está a pasta das fotos
        output_pdf = folder.parent / f"{folder.name}.pdf"
        
        print(f"\nA compilar {len(pdf_pages)} páginas no PDF...")
        
        # O Pillow permite gerar o PDF guardando a primeira imagem e anexando as restantes
        pdf_pages[0].save(
            output_pdf,
            "PDF",
            resolution=150.0,
            save_all=True,
            append_images=pdf_pages[1:]
        )
        print(f"Sucesso! O teu PDF foi guardado em: {output_pdf}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Converte fotos (HEIC, JPEG, PNG) de uma pasta para um PDF com imagens centradas.")
    parser.add_argument("pasta", help="Caminho para a pasta que contém as fotos.")
    args = parser.parse_args()
    
    create_pdf_from_photos(args.pasta)