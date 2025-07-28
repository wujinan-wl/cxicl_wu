cache_dir=$(grep proxy_cache_path /usr/local/openresty/nginx/conf/nginx.conf | awk '{print $2}' | tr -s '/' )
if [[ "$cache_dir" == "" || "$cache_dir" == "/"  ]];then
    echo "无法获取缓存目录"
else 
   rm -rf ${cache_dir}/*
fi

