# Load env and start containers
Get-Content .env | ForEach-Object {
    if (\ -match '^([^#][^=]*)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable(\[1].Trim(), \[2].Trim())
    }
}
docker-compose -f docker/docker-compose.yml up -d
