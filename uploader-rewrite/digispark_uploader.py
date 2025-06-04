import os
import subprocess
import shutil
import urllib.request
import zipfile
from tqdm import tqdm

PATH_FILE = 'CLIPath.txt'
CLI_ZIP_URL = 'https://github.com/arduino/arduino-cli/releases/download/v0.35.3/arduino-cli_0.35.3_Windows_64bit.zip'
CLI_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), 'arduino-cli'))
CLI_ZIP_FILE = os.path.join(os.path.dirname(__file__), 'arduino-cli.zip')
CLI_EXE = os.path.join(CLI_DIR, 'arduino-cli.exe')
SKETCH_ZIP_URL = 'https://github.com/huh445/Digispark-Scripts/archive/refs/heads/main.zip'
SKETCH_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), 'sketches'))
SKETCH_ZIP_FILE = os.path.join(os.path.dirname(__file__), 'sketches.zip')
BOARD = 'digistump:avr:digispark-tiny'

def run_cmd(cmd):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr)
        raise RuntimeError(f"Command failed with exit {result.returncode}")
    return result.stdout

def download_file(url, dest):
    with urllib.request.urlopen(url) as response:
        total = response.length
        with open(dest, 'wb') as out_file, tqdm(
            total=total, unit='B', unit_scale=True, desc=os.path.basename(dest)
        ) as pbar:
            while True:
                chunk = response.read(16 * 1024)
                if not chunk:
                    break
                out_file.write(chunk)
                pbar.update(len(chunk))
    print(f"Downloaded to {dest}")

def unzip(src, dest):
    if not os.path.isfile(src) or os.path.getsize(src) == 0:
        raise FileNotFoundError(f"{src} is empty or missing")
    with zipfile.ZipFile(src, 'r') as zip_ref:
        members = zip_ref.infolist()
        with tqdm(total=len(members), desc="Extracting", unit="files") as pbar:
            for member in members:
                zip_ref.extract(member, dest)
                pbar.update(1)
    print("Extraction complete")

def install_cli():
    shutil.rmtree(CLI_DIR, ignore_errors=True)
    print("Downloading and installing Arduino-CLI...")
    download_file(CLI_ZIP_URL, CLI_ZIP_FILE)
    unzip(CLI_ZIP_FILE, CLI_DIR)
    os.remove(CLI_ZIP_FILE)
    config_path = os.path.expanduser("~/.arduino15/arduino-cli.yaml")
    if not os.path.exists(config_path):
        run_cmd(f'"{CLI_EXE}" config init')
    else:
        print("Arduino CLI config already exists, skipping init.")
    run_cmd(f'"{CLI_EXE}" config add board_manager.additional_urls https://raw.githubusercontent.com/digistump/arduino-boards-index/master/package_digistump_index.json')
    run_cmd(f'"{CLI_EXE}" core install digistump:avr')
    with open(PATH_FILE, 'w') as f:
        f.write(f'"{CLI_EXE}"')
    print(f"Arduino-CLI installed at {CLI_EXE}")

def fetch_sketches():
    shutil.rmtree(SKETCH_DIR, ignore_errors=True)
    print("Fetching sketches from GitHub...")
    download_file(SKETCH_ZIP_URL, SKETCH_ZIP_FILE)
    unzip(SKETCH_ZIP_FILE, SKETCH_DIR)
    os.remove(SKETCH_ZIP_FILE)

def has_digispark(cli):
    try:
        output = run_cmd(f'"{cli}" core list')
        return any('digistump:avr' in line for line in output.splitlines())
    except:
        return False

def verify_cli():
    if os.path.exists(PATH_FILE):
        with open(PATH_FILE, 'r') as f:
            cli = f.read().strip().strip('"')
        if os.path.exists(cli) and has_digispark(cli):
            return cli
    if os.path.exists(CLI_EXE) and has_digispark(CLI_EXE):
        with open(PATH_FILE, 'w') as f:
            f.write(f'"{CLI_EXE}"')
        return CLI_EXE
    install_cli()
    return CLI_EXE

def list_sketches():
    return [os.path.join(root, file)
            for root, _, files in os.walk(SKETCH_DIR)
            for file in files if file.endswith('.ino')]

def choose_sketch(sketches):
    for i, sketch in enumerate(sketches):
        print(f"{i + 1}. {os.path.basename(sketch)}")
    index = int(input("Select sketch number: ")) - 1
    return sketches[index]

def compile_and_upload(cli, sketch):
    run_cmd(f'"{cli}" compile -b {BOARD} "{sketch}"')
    print("Compilation successful.")
    print("Please plug in Digispark now...")
    import time; time.sleep(2)
    run_cmd(f'"{cli}" upload -b {BOARD} "{sketch}"')
    print("Upload complete.")

def main():
    cli = verify_cli()
    fetch_sketches()
    sketches = list_sketches()
    if not sketches:
        raise RuntimeError("No sketches found.")
    sketch = choose_sketch(sketches)
    compile_and_upload(cli, sketch)

if __name__ == "__main__":
    main()