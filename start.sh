#!/bin/bash

export TEXTDOMAINDIR=$( cd "$( dirname "$0" )" && pwd )/locale

LANGUAGE=$2 bash $( cd "$( dirname "$0" )" && pwd )/$1.sh "$2"
