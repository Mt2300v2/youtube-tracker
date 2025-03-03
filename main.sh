#!/bin/bash

# Input file containing channel URLs
input_file="channels.txt"

# Base output CSV file name
base_output_file="video_data"
output_file="${base_output_file}_1.csv"
file_counter=1

# Maximum file size in bytes (95MB)
max_file_size=$((95 * 1024 * 1024))

# Current date and time for timestamp
timestamp=$(date +"%Y-%m-%d %H:%M:%S")

# Check if input file exists
if [[ ! -f "$input_file" ]]; then
  echo "Error: Input file '$input_file' not found."
  exit 1
fi

# Create CSV header if the file doesn't exist
if [[ ! -f "$output_file" ]]; then
  echo "Timestamp,Channel URL,Title,Video URL,Owner Channel Name,Views,Rounded Subscriber Count,Description,Like Count" > "$output_file"
fi

# Function to check file size and create a new file if necessary
check_file_size() {
  if [[ -f "$output_file" ]]; then
    file_size=$(stat -c%s "$output_file")
    if [[ "$file_size" -gt "$max_file_size" ]]; then
      file_counter=$((file_counter + 1))
      output_file="${base_output_file}_${file_counter}.csv"
      echo "Creating new output file: $output_file"
      echo "Timestamp,Channel URL,Title,Video URL,Owner Channel Name,Views,Rounded Subscriber Count,Description,Like Count" > "$output_file"
    fi
  fi
}

# Debug flag
debug_mode=false

# Check for debug flag
if [[ "$1" == "--debug" ]]; then
  debug_mode=true
  echo "Debug mode enabled. Script will terminate after the first batch."
fi

# Read channel URLs from input file
while true; do #loop forever until timeout or debug mode
  while IFS= read -r line; do
    # Remove trailing comma if present
    channel_url=$(echo "$line" | sed 's/,//')

    # Check if URL is empty
    if [[ -z "$channel_url" ]]; then
      continue
    fi

    echo "Parsing data from: $channel_url"

    # Curl the HTML content with specified headers
    stats=$(curl -sL "$channel_url" \
      -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36" \
      -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
      -H "Accept-Language: en-US,en;q=0.9" \
      -H "Connection: keep-alive" | tr -d '\n')

    # Extract video titles and URLs
    video_data=$(echo "$stats" | grep -oP '"title":{"runs":\[{"text":"(.*?)"},"navigationEndpoint":{"clickTrackingParams":"[^"]*","commandMetadata":{"webCommandMetadata":{"url":"(\/watch\?v=[^"]*)"')

    # Check if any titles and URLs were found
    if [[ -z "$video_data" ]]; then
      echo "No video titles or URLs found for $channel_url."
      continue
    fi

    # Process each video
    while IFS= read -r data; do
      title=$(echo "$data" | grep -oP '"title":{"runs":\[{"text":"(.*?)"}')
      title=$(echo "$title" | sed 's/"title":{"runs":\[{"text":"//g; s/"}//g')
      url=$(echo "$data" | grep -oP '"url":"(\/watch\?v=[^"]*)"')
      url=$(echo "$url" | sed 's/"url":"//g; s/"//g')

      if [[ -n "$title" && -n "$url" ]]; then
        # Filter out unwanted results.
        if ! [[ "$title" =~ (Keyboard shortcuts|Playback|General|Subtitles and closed captions|Spherical Videos) ]]; then
          full_url="https://www.youtube.com$url"

          # Get video stats
          video_stats=$(curl -sL "$full_url" \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
            -H "Accept-Language: en-US,en;q=0.9" \
            -H "Connection: keep-alive" | tr -d '\n')

          owner_channel_name=$(echo "$video_stats" | grep -oP '"ownerChannelName":"\K[^"]+' | head -n 1)
          views=$(echo "$video_stats" | grep -oP '"viewCount":\s*{"simpleText":"\K[^"]+' | head -n 1)
          subscriber_count=$(echo "$video_stats" | grep -oP '\"sectionSubtitle\":.*?\"simpleText\":\"\K[^\"]+' | head -n 1)
          description=$(echo "$video_stats" | grep -oP '"description":\s*{"simpleText":"\K[^"]+' | head -n 1)
          description=$(echo "$description" | sed 's/\\n/\n/g')
          like_count=$(echo "$video_stats" | grep -oP '"factoidRenderer":{"value":{"simpleText":"\K[^"]+"' | grep -m 1 -oE '[0-9.,KMB]+')

          # Remove commas from numerical values
          views=$(echo "$views" | sed 's/,//g')
          subscriber_count=$(echo "$subscriber_count" | sed 's/,//g')
          like_count=$(echo "$like_count" | sed 's/,//g')

          # Escape commas in other values for CSV
          title=$(echo "$title" | sed 's/,/\\,/g')
          owner_channel_name=$(echo "$owner_channel_name" | sed 's/,/\\,/g')
          description=$(echo "$description" | sed 's/,/\\,/g')

          # Append data to CSV file
          echo "$timestamp,$channel_url,$title,$full_url,$owner_channel_name,$views,$subscriber_count,\"$description\",$like_count" >> "$output_file"

          #check file size after each append
          check_file_size
          echo "Currently parsed: $title"
        fi
      fi
    done <<< "$video_data"
  done < "$input_file"
  if $debug_mode ; then
    echo "Debug mode, exiting after first batch"
    break;
  fi
done
