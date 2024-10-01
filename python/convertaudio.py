from pydub import AudioSegment

def convert_mp3_to_m4a(mp3_file_path, m4a_file_path):
    # Load the MP3 file
    audio = AudioSegment.from_mp3(mp3_file_path)
    
    # Export as M4A
    audio.export(m4a_file_path, format="m4a")

if __name__ == "__main__":
    mp3_file_path = "input.mp3"  # Replace with your input MP3 file path
    m4a_file_path = "output.m4a"  # Replace with your desired output M4A file path
    
    convert_mp3_to_m4a(mp3_file_path, m4a_file_path)
    print(f"Converted {mp3_file_path} to {m4a_file_path}")