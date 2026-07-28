import os
import fitz  # PyMuPDF
from pathlib import Path

def convert_pdfs_to_txt(source_dir, target_dir):
    source_path = Path(source_dir)
    target_path = Path(target_dir)

    # Cria a pasta de destino se não existir
    if not target_path.exists():
        target_path.mkdir(parents=True)
        print(f"Pasta criada: {target_dir}")

    # Lista todos os PDFs na pasta de origem
    pdf_files = list(source_path.glob("*.pdf"))

    if not pdf_files:
        print("Nenhum arquivo PDF encontrado na pasta de origem.")
        return

    print(f"Iniciando conversão de {len(pdf_files)} arquivos...\n")

    for pdf_file in pdf_files:
        txt_filename = pdf_file.stem + ".txt"
        txt_path = target_path / txt_filename

        # Pula se o TXT já existir (para poupar tempo)
        if txt_path.exists():
            print(f"[-] Pulando {pdf_file.name} (já convertido)")
            continue

        try:
            print(f"[+] Convertendo {pdf_file.name}...")

            # Abre o PDF
            doc = fitz.open(pdf_file)
            full_text = ""

            # Extrai texto de cada página
            for page in doc:
                full_text += page.get_text() + "\n"

            # Salva o resultado
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(full_text)

            doc.close()

        except Exception as e:
            print(f"[!] Erro ao converter {pdf_file.name}: {e}")

    print("\nConversão concluída!")

if __name__ == "__main__":
    # Caminhos baseados na estrutura que você me passou
    KNOWLEDGE_DIR = r"C:\Users\wesle\AndroidStudioProjects\sanf\lib\knowledge"

    # Rodar a conversão
    convert_pdfs_to_txt(KNOWLEDGE_DIR, KNOWLEDGE_DIR)