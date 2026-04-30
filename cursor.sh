#!/bin/bash

LOCAL_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            LOCAL_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 --dir /path/to/directory"
            exit 1
            ;;
    esac
done

if [ -z "$LOCAL_DIR" ]; then
    echo "Error: --dir argument is required!"
    echo "Usage: $0 --dir /path/to/directory"
    exit 1
fi

if [ ! -d "$LOCAL_DIR" ]; then
    echo "Error: Directory '$LOCAL_DIR' does not exist!"
    exit 1
fi

echo "Building cursor image..."
docker build -t cursor .

echo "Running container with directory: $LOCAL_DIR"

docker run -it -v $HOME/.gradle:/root/.gradle -v "$LOCAL_DIR:/cursor" cursor /bin/bash
