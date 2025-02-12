#!/bin/bash
# for exception
set -e
## for debug.
# set -v
# set -x

FLINK_URL=`sed '/^FLINK_URL=/!d;s/.*=//' flink-parcel.properties` 
FLINK_VERSION=`sed '/^FLINK_VERSION=/!d;s/.*=//' flink-parcel.properties`
FLINK_SHA512=`sed '/^FLINK_SHA512=/!d;s/.*=//' flink-parcel.properties`
EXTENS_VERSION=`sed '/^EXTENS_VERSION=/!d;s/.*=//' flink-parcel.properties`
OS_VERSION=`sed '/^OS_VERSION=/!d;s/.*=//' flink-parcel.properties`
CDH_MIN_FULL=`sed '/^CDH_MIN_FULL=/!d;s/.*=//' flink-parcel.properties`
CDH_MIN=`sed '/^CDH_MIN=/!d;s/.*=//' flink-parcel.properties`
CDH_MAX_FULL=`sed '/^CDH_MAX_FULL=/!d;s/.*=//' flink-parcel.properties`
CDH_MAX=`sed '/^CDH_MAX=/!d;s/.*=//' flink-parcel.properties`

base_dir="$(cd `dirname $0`/;pwd)"
build_dir="${base_dir}/build"; mkdir -p ${build_dir}
flink_service_name="flink"
flink_service_name_lower="$(echo $flink_service_name | tr '[:upper:]' '[:lower:]')"
flink_archive_file="${base_dir}/material/$(basename $FLINK_URL)"
flink_build_name="${flink_service_name_lower}-${FLINK_VERSION}-${EXTENS_VERSION}"
flink_unzip_dir="${build_dir}/${flink_build_name}"
## for example: flink-1.11.2-bin-scala_2.12
flink_package_lower="$(basename $flink_archive_file .tgz)"
## The CDH install default parcel dir example is: /opt/clouera/parcel-repo/
flink_parcel_dir="${build_dir}/parcel-repo"
## The CDH install default parcel path example is: /opt/clouera/parcel-repo/CDH-6.3.1-1.cdh6.3.1.p0.1470567-el7.parcel
flink_parcel_file="${flink_parcel_dir}/${flink_package_lower}-${OS_VERSION}.parcel"
flink_build_parent_dir="${build_dir}/.parcels"
flink_build_tmp_dir="${flink_build_parent_dir}/${flink_build_name}"
flink_install_default_dir="/opt/cloudera/parcels/${flink_build_name}"
## The CDH install default libs parcels dir example is: /opt/cloudera/parcels/CDH-6.3.1-1.cdh6.3.1.p0.1470567/lib/spark/
## The CDH install default csd dir is: /opt/cloudera/csd
flink_csd_build_dir="${build_dir}/csd"

function build_cm_ext() {
  if [ ! -d cm_ext ]; then
    git clone https://github.com/cloudera/cm_ext.git
  fi
  if [ ! -f cm_ext/validator/target/validator.jar ]; then
    cd cm_ext
    #git checkout "$CM_EXT_BRANCH"
    mvn install -U -Dmaven.test.skip=true
    cd ..
  fi
}

function get_flink() {
  if [ ! -f "$flink_archive_file" ]; then
    curl -SLk -o ${flink_archive_file} $FLINK_URL
  else
    echo "INFO: Found material archive file: $flink_archive_file"
  fi
  flink_sha512="$( sha512sum $flink_archive_file | cut -d' ' -f1 )"
  if [ "$flink_sha512" != "$FLINK_SHA512" ]; then
    echo "ERROR: sha512 checksum of $flink_archive_file is not correct"
    exit 1
  fi
  if [ ! -d "$flink_unzip_dir" ]; then
    mkdir -p ${flink_unzip_dir}
    tar -xf $flink_archive_file --strip-components=1 -C ${flink_unzip_dir}
  else
    echo "ERROR: Already directory of $flink_unzip_dir, Please use sub command for 'clean"
    exit 1
  fi
}

function build_flink_parcel() {
  if [ -f "$flink_parcel_file" ] && [ -f "$flink_parcel_dir/manifest.json" ]; then
    echo "WARN: Found parcel package that has been built prev: '$flink_parcel_file', Please remove it and re-build. or use sub command 'clean'"
    return
  fi
  if [ ! -d $flink_build_tmp_dir ]; then
    get_flink
    mkdir -p $flink_build_tmp_dir/lib
    mv ${flink_unzip_dir} ${flink_build_tmp_dir}/lib/${flink_service_name_lower}
  fi
  # Make scripts into bin.
  chmod 755 ${base_dir}/flink-parcel-src/bin/flink*
  local bin_dir=${flink_build_tmp_dir}/lib/${flink_service_name_lower}/bin
  cp -r ${base_dir}/flink-parcel-src/bin/flink-master.sh $bin_dir
  cp -r ${base_dir}/flink-parcel-src/bin/flink-worker.sh $bin_dir
  cp -r ${base_dir}/flink-parcel-src/bin/flink-yarn.sh $bin_dir
  # Make parcel meta config.
  local flink_build_meta_dir=${flink_build_tmp_dir}/meta
  mkdir -p $flink_build_meta_dir
  cp -r ${base_dir}/flink-parcel-src/meta/* $flink_build_meta_dir/
  sed -i -e "s#%flink_version%#$flink_install_default_dir#g" $flink_build_meta_dir/flink_env.sh
  sed -i -e "s#%VERSION%#$FLINK_VERSION#g" $flink_build_meta_dir/parcel.json
  sed -i -e "s#%EXTENS_VERSION%#$EXTENS_VERSION#g" $flink_build_meta_dir/parcel.json
  sed -i -e "s#%CDH_MAX_FULL%#$CDH_MAX_FULL#g" $flink_build_meta_dir/parcel.json
  sed -i -e "s#%CDH_MIN_FULL%#$CDH_MIN_FULL#g" $flink_build_meta_dir/parcel.json
  sed -i -e "s#%SERVICENAME%#$flink_service_name#g" $flink_build_meta_dir/parcel.json
  sed -i -e "s#%SERVICENAMELOWER%#$flink_service_name_lower#g" $flink_build_meta_dir/parcel.json
  java -jar cm_ext/validator/target/validator.jar -d ${flink_build_tmp_dir}
  # Make parcel file with build directory.
  mkdir -p $flink_parcel_dir
  cd $flink_build_tmp_dir/../
  tar -zcvhf $flink_parcel_file $flink_build_name --owner=root --group=root
  java -jar ${base_dir}/cm_ext/validator/target/validator.jar -f $flink_parcel_file
  # Make manifest.json with parcel file.
  python ${base_dir}/cm_ext/make_manifest/make_manifest.py $flink_parcel_dir
  sha1sum $flink_parcel_file | awk '{print $1}' > ${flink_parcel_file}.sha
  rm -rf $flink_build_parent_dir
}

function build_flink_csd_on_yarn() {
  local jarname=${build_dir}/${flink_service_name}_on_yarn-${FLINK_VERSION}.jar
  if [ -f "$jarname" ]; then
    echo "WARN: Found csd_on_yarn jar that has been built prev: '$flink_parcel_file', Please remove it and re-build. or use sub command 'clean'"
    return
  fi
  rm -rf ${jarname}
  local tmp_dir=${build_dir}/.tmp; mkdir -p ${tmp_dir}
  cp -rf ${base_dir}/flink-csd-on-yarn-src/* ${tmp_dir}/
  sed -i -e "s#%SERVICENAME%#$livy_service_name#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%SERVICENAMELOWER%#$flink_service_name_lower#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%VERSION%#$FLINK_VERSION#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%CDH_MIN%#$CDH_MIN#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%CDH_MAX%#$CDH_MAX#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%SERVICENAMELOWER%#$flink_service_name_lower#g" ${tmp_dir}/scripts/control.sh
  java -jar ${base_dir}/cm_ext/validator/target/validator.jar -s ${tmp_dir}/descriptor/service.sdl -l "SPARK_ON_YARN SPARK2_ON_YARN"
  jar -cvf ${jarname} -C ${tmp_dir} .
  rm -rf ${tmp_dir}
  mkdir -p ${flink_csd_build_dir}
  mv ${jarname} ${flink_csd_build_dir}
}

function build_flink_csd_standalone() {
  local jarname=${build_dir}/${flink_service_name}_standalone-${FLINK_VERSION}.jar
  if [ -f "$jarname" ]; then
    echo "WARN: Found csd_on_standalone jar that has been built prev: '$flink_parcel_file', Please remove it and re-build. or use sub command 'clean'"
    return
  fi
  rm -rf ${jarname}
  local tmp_dir=${build_dir}/.tmp; mkdir -p ${tmp_dir}
  cp -rf ${base_dir}/flink-csd-standalone-src/* ${tmp_dir}/
  sed -i -e "s#%VERSIONS%#$FLINK_VERSION#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%CDH_MIN%#$CDH_MIN#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%CDH_MAX%#$CDH_MAX#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%SERVICENAME%#$livy_service_name#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%SERVICENAMELOWER%#$flink_service_name_lower#g" ${tmp_dir}/descriptor/service.sdl
  sed -i -e "s#%SERVICENAMELOWER%#$flink_service_name_lower#g" ${tmp_dir}/scripts/control.sh
  java -jar ${base_dir}/cm_ext/validator/target/validator.jar -s ${tmp_dir}/descriptor/service.sdl -l "SPARK_ON_YARN SPARK2_ON_YARN"
  jar -cvf ${jarname} -C ${tmp_dir} .
  rm -rf ${tmp_dir}
  mkdir -p ${flink_csd_build_dir}
  mv ${jarname} ${flink_csd_build_dir}
}

case $1 in
parcel)
  build_cm_ext
  build_flink_parcel
  ;;
csd_on_yarn)
  build_flink_csd_on_yarn
  ;;
csd_standalone)
  build_flink_csd_standalone
  ;;
clean)
  /bin/rm -rf ${build_dir}
  ;;
*)
  echo "Usage: $0 {parcel|csd_on_yarn|csd_standalone|clean}"
  ;;
esac