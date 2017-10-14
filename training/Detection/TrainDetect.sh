#!/bin/bash 

declare -r PROJECT=$(gcloud config list project --format "value(core.project)")
declare -r BUCKET="gs://${PROJECT}-ml"
declare -r MODEL_NAME="DeepMeerkatDetection"
declare -r FOLDER="${BUCKET}/${MODEL_NAME}"
declare -r JOB_ID="${MODEL_NAME}_$(date +%Y%m%d_%H%M%S)"
declare -r TRAIN_DIR="${FOLDER}/${JOB_ID}"
declare -r EVAL_DIR="${BUCKET}/${MODEL_NAME}/${JOB_ID}_eval"

#Converted labeled records to TFrecords format
python PrepareData.py

#copy tfrecords and config file to the cloud
gsutil cp -r /Users/Ben/Dropbox/GoogleCloud/Detection/tfrecords/ ${FOLDER}
gsutil cp faster_rcnn_inception_resnet_v2_atrous_coco.config ${FOLDER}
gsutil cp cloud.yml ${FOLDER}
gsutil cp label.pbtxt ${FOLDER}/tfrecords

#not clear if it should go in records folder
gsutil cp label.pbtxt ${FOLDER}

#upload checkpoint if it doesn't exist
gsutil cp -n -r checkpoint/ ${FOLDER}

declare -r PIPELINE_CONFIG_PATH="${FOLDER}/faster_rcnn_inception_resnet_v2_atrous_coco.config"
declare -r PIPELINE_YAML="/Users/Ben/Documents/DeepMeerkat/training/Detection/cloud.yml"

#package to send to the cloud
cd models/research

python setup.py sdist
(cd slim && python setup.py sdist)

#Training

gcloud ml-engine jobs submit training "${JOB_ID}_train" \
    --job-dir=${TRAIN_DIR} \
    --packages dist/object_detection-0.1.tar.gz,slim/dist/slim-0.1.tar.gz \
    --module-name object_detection.train \
    --region us-central1 \
    --config ${PIPELINE_YAML} \
    -- \
    --train_dir=${TRAIN_DIR} \
    --pipeline_config_path= ${PIPELINE_CONFIG_PATH}

#evalution job
gcloud ml-engine jobs submit training object_detection_eval_`date +%s` \
    --job-dir=${TRAIN_DIR} \
    --packages dist/object_detection-0.1.tar.gz,slim/dist/slim-0.1.tar.gz \
    --module-name object_detection.eval \
    --region us-central1 \
    --scale-tier BASIC_GPU \
    -- \
    --checkpoint_dir=${TRAIN_DIR} \
    --eval_dir=${EVAL_DIR} \
    --pipeline_config_path=${PIPELINE_CONFIG_PATH}
    
tensorboard --logdir=${TRAIN_DIR}