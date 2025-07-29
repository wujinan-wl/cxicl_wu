CACHE_DIR="/data/nginx/cache/"

if [[ -z "$CACHE_DIR" || "$CACHE_DIR" == "/" ]]; then
  echo "无法获取缓存目录"
else
  rm -rf $CACHE_DIR/*
fi
