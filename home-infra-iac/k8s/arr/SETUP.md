# arr Stack — Post-Deploy Configuration

The Kubernetes manifests get the apps running, but Sonarr/Radarr/Prowlarr all need one-time in-UI configuration before they actually do anything useful. This doc covers that.

## URLs

- Prowlarr: https://prowlarr.example.com
- Sonarr: https://sonarr.example.com
- Radarr: https://radarr.example.com

## Filesystem layout (what each pod sees)

| Pod         | Mount              | Points at (NFS server)   |
|-------------|--------------------|--------------------------|
| qBittorrent | `/downloads`       | `/mnt/my-nfs/downloads` |
| Plex        | `/media`           | `/mnt/my-nfs/media`     |
| **arr**     | **`/data`**        | **`/mnt/my-nfs`**       |

The arr apps mount the NFS *root* so they can see both `/data/downloads` and `/data/media` on the same filesystem — this is the requirement for hardlinks to work between them. qBittorrent and Plex stay scoped to their subtrees.

## 1. Prowlarr — indexer manager

1. Open Prowlarr, go through the auth setup wizard (pick Basic or Forms).
2. **Settings → Apps → Add Application** for each of Sonarr and Radarr:
   - Sonarr:
     - Prowlarr Server: `http://prowlarr:9696` (auto-filled)
     - Sonarr Server: `http://sonarr:8989`
     - API Key: grab from Sonarr → Settings → General
   - Radarr:
     - Radarr Server: `http://radarr:7878`
     - API Key: grab from Radarr → Settings → General
3. **Indexers → Add Indexer** — add your indexers here (not in Sonarr/Radarr). Prowlarr syncs them.

## 2. Sonarr — TV

1. Auth setup wizard.
2. **Settings → Media Management → Root Folders → Add**: `/data/media/tv`
3. **Settings → Download Clients → Add → qBittorrent**:
   - Host: `qbittorrent.qbittorrent.svc.cluster.local`
   - Port: `8080`
   - Username/password: from qBittorrent web UI
   - Category: `tv` (lets qBittorrent separate TV downloads in its own folder)
4. **Settings → Media Management**:
   - Check "Use Hardlinks instead of Copy" (under Importing)
   - Check "Rename Episodes" if you want Plex-friendly names
5. **Remote Path Mapping** (Settings → Download Clients → Advanced) — tells Sonarr that qBittorrent's `/downloads` is Sonarr's `/data/downloads`:
   - Host: `qbittorrent.qbittorrent.svc.cluster.local`
   - Remote Path: `/downloads/`
   - Local Path: `/data/downloads/`

## 3. Radarr — Movies

Same as Sonarr with these differences:
- Root folder: `/data/media/movies`
- Download client category: `movies`

## 4. Verify hardlinks

After the first successful import, confirm it actually hardlinked (not copied):

```bash
ssh myadmin@192.168.1.125
# inside nfs-01:
stat /mnt/my-nfs/downloads/complete/<some-file>
stat /mnt/my-nfs/media/tv/<imported-file>
# Links count should be 2, and Inode should match between them.
```

If Links is 1 on both files, they were copied — check the "Use Hardlinks" setting and the remote path mapping.

## Migrating existing library

For the media you've already hardlinked manually:

- **Sonarr**: add a Series, point it at your existing `/data/media/tv/Show Name/` — it'll scan and match. No re-download.
- **Radarr**: same — Add Movie → point at existing file.

Sonarr/Radarr don't care that the files are already hardlinks; they'll take ownership without rescanning qBittorrent.

## qBittorrent categories (optional, but cleaner)

In qBittorrent: Settings → Downloads → enable "Automatic Torrent Management" and create categories `tv` and `movies` with save paths:

- tv: `/downloads/complete/tv`
- movies: `/downloads/complete/movies`

Sonarr/Radarr will use these when sending new downloads, and your existing stuff in `/downloads/complete/` stays untouched.
