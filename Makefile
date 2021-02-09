SHELL := /bin/bash

prep_dir = preparation
img_dir = image

meta_data_dir = meta-data

layer_0_dir = $(prep_dir)/layer_0
layer_0_server_dir = $(layer_0_dir)/server
layer_0_file = $(img_dir)/layer_0.tar

layer_1_dir = $(prep_dir)/layer_1
layer_1_www_dir = $(layer_1_dir)/www
layer_1_file = $(img_dir)/layer_1.tar

image_file = image.tar

container_name = manual_container
container_host_port = 8080

clean:
	@rm -fr "${prep_dir}"
	@rm -fr "${img_dir}"
	@rm -f "${image_file}"
	@rm -f "./server/serve"

dirs: clean
	@mkdir "${prep_dir}"
	@mkdir "${img_dir}"

serve:
	cd ./server; \
	env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o serve

layer_0.tar: dirs serve
	@mkdir -p "${layer_0_server_dir}"
	cp "./server/serve" "${layer_0_server_dir}/"
	tar -cf "${layer_0_file}" -C "${layer_0_dir}" .

layer_1.tar: dirs
	@mkdir -p "${layer_1_www_dir}"
	cp "./server/index.html" "${layer_1_www_dir}/"
	tar -cf "${layer_1_file}" -C "${layer_1_dir}" .

manifest.json: dirs
	cp "${meta_data_dir}/manifest.json" "${img_dir}/"

config.json: dirs layer_0.tar layer_1.tar
	@set -e; \
	layer_0_diffid=$$(sha256sum ${layer_0_file} | awk '{print $$1}'); \
	layer_1_diffid=$$(sha256sum ${layer_1_file} | awk '{print $$1}'); \
	config=$$(cat ${meta_data_dir}/config.json.tmpl); \
	config=$${config/LAYER_0_DIFFID/$$layer_0_diffid}; \
	config=$${config/LAYER_1_DIFFID/$$layer_1_diffid}; \
	echo $$config > "${img_dir}/config.json"

image.tar: manifest.json config.json layer_0.tar layer_1.tar
	tar -cf "${image_file}" -C "${img_dir}" .

build: image.tar

load: image.tar
	docker load --input "${image_file}"

run: load
	docker rm -f "${container_name}" > /dev/null 2>&1
	docker run -d --name "${container_name}" -p ${container_host_port}:8080 manual-mini-image:1.1

test: run
	curl http://localhost:${container_host_port}
