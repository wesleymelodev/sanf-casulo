import os
from pathlib import Path
from PIL import Image

# Configurações de execução
# O script assume que está dentro da pasta 'scripts/', logo o alvo está um nível acima, em 'assets/'
DIRETORIO_RAIZ = Path(__file__).resolve().parent.parent
#DIRETORIO_ASSETS = DIRETORIO_RAIZ / "assets"
DIRETORIO_ASSETS = DIRETORIO_RAIZ
QUALIDADE_WEBP = 82  # Índice de 0 a 100 (82 entrega excelente precisão visual e baixo peso)
DELETAR_ORIGINAL = True  # Define como True para apagar os arquivos pesados após converter

def converter_para_webp():
    if not DIRETORIO_ASSETS.exists():
        print(f"[ERRO] Diretório não encontrado: {DIRETORIO_ASSETS}")
        return

    extensoes_alvo = (".png", ".ico", ".jpeg")
    total_arquivos = 0
    peso_inicial_bytes = 0
    peso_final_bytes = 0

    print(f"Iniciando varredura em: {DIRETORIO_ASSETS}\n")

    for raiz, _, arquivos in os.walk(DIRETORIO_ASSETS):
        for arquivo in arquivos:
            caminho_arquivo = Path(raiz) / arquivo

            if caminho_arquivo.suffix.lower() in extensoes_alvo:
                total_arquivos += 1
                tamanho_original = caminho_arquivo.stat().st_size
                peso_inicial_bytes += tamanho_original

                # Define o caminho do novo arquivo .webp
                caminho_webp = caminho_arquivo.with_suffix(".ico")

                try:
                    with Image.open(caminho_arquivo) as img:
                        # Converte para RGB se for RGBA (PNG com transparência é suportado nativamente pelo WebP)
                        img.save(caminho_webp, "ico", quality=QUALIDADE_WEBP, method=6)

                    tamanho_novo = caminho_webp.stat().st_size
                    peso_final_bytes += tamanho_novo
                    reducao = ((tamanho_original - tamanho_novo) / tamanho_original) * 100

                    print(f"[CONVERTIDO] {arquivo} -> {caminho_webp.name} | Redução: {reducao:.1f}%")

                    if DELETAR_ORIGINAL and caminho_arquivo != caminho_webp:
                        caminho_arquivo.unlink()

                except Exception as e:
                    print(f"[FALHA] Não foi possível processar {arquivo}: {e}")

    # Exibição de métricas finais
    if total_arquivos > 0:
        peso_ini_mb = peso_inicial_bytes / (1024 * 1024)
        peso_fin_mb = peso_final_bytes / (1024 * 1024)
        economia_mb = peso_ini_mb - peso_fin_mb

        print("\n--- Relatório de Otimização ---")
        print(f"Arquivos processados: {total_arquivos}")
        print(f"Peso original total:  {peso_ini_mb:.2f} MB")
        print(f"Peso final (WebP):    {peso_fin_mb:.2f} MB")
        print(f"Espaço liberado:      {economia_mb:.2f} MB")
    else:
        print("Nenhum arquivo PNG, JPG ou JPEG encontrado para conversão.")

if __name__ == "__main__":
    converter_para_webp()