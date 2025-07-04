from moviepy import AudioFileClip, ImageClip, CompositeVideoClip

def audio_to_video(audio_file, image_file, output_file):
    # Load the audio file
    audio_clip = AudioFileClip(audio_file)
    
    # Load the image file
    image_clip = ImageClip(image_file).with_duration(audio_clip.duration)
    
    # Set the image size to match the audio duration
    image_clip = image_clip.with_duration(audio_clip.duration).with_fps(24)
    
    # Combine audio and image into a video
    video = CompositeVideoClip([image_clip.with_audio(audio_clip)])
    
    # Write the result to a file
    video.write_videofile(output_file, codec='libx264', audio_codec='aac')

if __name__ == "__main__":
    audio_file = "audiofile.m4a"  # Replace with your audio file path
    image_file = "imagefile.jpg"  # Replace with your image file path
    output_file = "output_video.mp4"           # Output video file name

    audio_to_video(audio_file, image_file, output_file)