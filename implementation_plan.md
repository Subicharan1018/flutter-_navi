# Implementation Plan: Local Music Shuffle Server

## Goal Description
The objective is to create a local Flask server that exposes an intelligent music shuffle API based on an existing `shuffle_model.py`. The server will be managed via a systemd service for automatic restarts, and a bash script will be provided to periodically rebuild the model via a cron job.

> [!IMPORTANT]
> **User Review Required**
> You provided a template with placeholders instead of the actual configuration details and the model file. I need this information to proceed accurately. Please review the Open Questions below and provide the missing details!

## Open Questions
> [!WARNING]
> Please provide the following missing information so I can proceed with the execution:
> 
> 1. **`shuffle_model.py`**: You didn't paste or attach the contents of `shuffle_model.py`. Please provide this file so I know how to correctly import and use `load_model()` and the prediction logic.
> 2. **Working Directory**: Do you want to use `/home/subi/shuffle` as the working directory?
> 3. **Python Path**: Is your python path `/usr/bin/python3`? Are you using a virtual environment (e.g., `/home/subi/shuffle/venv/bin/python`)?
> 4. **CSV Paths**: What are the paths for the **Apple Music CSV** and **FLAC metadata**? (I see Favorites is `/home/subi/Downloads/Apple_Music_-_Favorites.csv`).
> 5. **Port**: What port would you like the Flask server to run on? (e.g., `5000` or `8080`).

## Proposed Changes

### Flask Server (`shuffle_server.py`)
- Create a Flask app that imports `shuffle_model`.
- Call `load_model()` before starting the app to load `shuffle_model.json`.
- Expose `GET /next` parsing `current`, `artist`, `playlist`, and `count` parameters.
- Expose `GET /profile` to inspect a song's features.
- Expose `GET /health` to return a 200 OK status.

### Systemd Service (`shuffle.service`)
- Create a `[Unit]` and `[Service]` block.
- Set `WorkingDirectory` to your specified folder.
- Set `ExecStart` to run the Flask app (e.g., via `gunicorn` or raw `python3`).
- Configure `Restart=always` and `User=subi`.

### Rebuild Script (`rebuild_model.sh`)
- Create a bash script that executes `python3 shuffle_model.py --build` with the provided CSV paths.
- Add `set -e` to ensure it fails gracefully if an error occurs.
- Provide instructions on how to add this to `crontab`.

## Verification Plan
### Manual Verification
- Run `python3 shuffle_server.py` and test the endpoints via `curl`.
- Start the systemd service and check its status (`systemctl status shuffle.service`).
- Execute `rebuild_model.sh` to ensure it successfully builds the `shuffle_model.json` file.
