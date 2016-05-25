#!/usr/bin/env bash

###############################################################################
# Basic gene expression analysis pipeline for single end data using bowtie2
###############################################################################

###############################################################################
# BEFORE RUNNING SCRIPT DO THE FOLLOWING:
###############################################################################

# 1. Make sure modules are loaded:
#       bbmap
#       bowtie2
#       python (default version)

# The location of the following files may have to be modified in this script:
# bowtie index files
# merge_counts.py and small_rna_filter.py
# illumina adaptor sequences

# NOTE: Any read processing INCLUDING adapter trimming is not covered in this pipeline and must be performed beforehand.

###############################################################################
###############################################################################



usage="
    USAGE
       step1:   load the following modules: bbmap bowtie2 samtools python (default version)
       step2:   bash bowtie2_pipeline.sh [options]  

    ARGUMENTS
        -d/--dir
        Directory containing read files (can be .DIR .fasta or .txt (raw) format)
        
        -r/--reference
        Mapping reference (default: mrna)

        -f 
        filter for 22G RNAs ('g') 21U RNAs ('u') or both (gu)

        -c/--count
        Make a read count table
    "
# Set default parameters

REF="mrna"
MISMATCH="0"
FILTER=""
COUNT="false"

# Parse command line parameters

if [ -z "$1" ]; then
        echo "$usage"
        exit
fi

while [[ $# > 0 ]]
do
        key="$1"
        case $key in
                -d|--DIR)
                DIR="$2"
                shift
                ;;
                -r|--ref)
                REF="$2"
                shift
                ;;
                -m|--mismatch)
                MISMATCH="$2"
                ;;
                -f|filter)
                FILTER="$2"
                shift
                ;;
                -c|--count)
                COUNT="true"
                ;;
        esac
shift
done

# Remove trailing "/" from DIR directory if present

if [[ ${DIR:(-1)} == "/" ]]; then
        DIR=${DIR::${#DIR}-1}
fi

# parse filter option
case $FILTER in
        "g")
        FILTER_OPT="-g"
        ;;
        "u")
        FILTER_OPT="-u"
        ;;
        "gu"|"ug")
        FILTER_OPT="-u -g"
        ;;
esac

# Select bowtie index based on reference

case $REF in 
        "mrna")
        INDEX="/nas02/home/s/f/sfrenk/proj/seq/WS251/mrna/bowtie/mrna"
        ;;
        "transposons")
        INDEX="/proj/ahmedlab/steve/seq/transposons/bowtie/transposon"
        ;;
        "genome")
        INDEX="/proj/ahmedlab/steve/seq/WS251/genome/bowtie/genome"
        ;;
        "rdna")
        INDEX="/proj/ahmedlab/steve/seq/rdna/bowtie/rdna"
        ;;
esac

###############################################################################
###############################################################################

# Make directories
if [ ! -d "filtered" ]; then
        mkdir filtered
fi
if [ ! -d "bowtie_out" ]; then
        mkdir bowtie_out
fi
if [ ! -d "count" ] && [ ${COUNT} == "true" ]; then
        mkdir count
fi
if [ ! -d "bam" ]; then
        mkdir bam
fi

# Print out loaded modules to keep a record of which software versions were used in this run

modules=$(/nas02/apps/Modules/bin/modulecmd tcsh list 2>&1)
echo "$modules"

# Start pipeline

echo $(date +"%m-%d-%Y_%H:%M")" Starting pipeline..."

for file in ${DIR}/*
do
        FBASE=$(basename $file .txt)
        BASE=${FBASE%.*}

        # Extract 22G and or 21U RNAs or convert all reads to raw format
        python /proj/ahmedlab/steve/seq/util/small_rna_filter.py ${FILTER_OPT} -o ./filtered/${BASE}.txt $file

        # Map reads using Bowtie 2
        echo $(date +"%m-%d-%Y_%H:%M")" Mapping ${BASE} with Bowtie2..."

        bowtie -M 1 -r -S -v ${MISMATCH} -p 4 --best ${INDEX} ./filtered/${BASE}.txt ./bowtie_out/${BASE}.sam
     
        echo $(date +"%m-%d-%Y_%H:%M")" Mapped ${BASE}"
        
        # Convert to bam then sort

        echo $(date +"%m-%d-%Y_%H:%M")" Converting and sorting ${BASE}..."

        samtools view -bS ./bowtie_out/${BASE}.sam > ./bam/${BASE}.bam

        samtools sort -o ./bam/${BASE}_sorted.bam ./bam/${BASE}.bam 

        # Need to index the sorted bam files for visualization

        echo $(date +"%m-%d-%Y_%H:%M")" Indexing ${BASE}..."

        samtools index ./bam/${BASE}_sorted.bam

        # Count reads that map antisense to genes
        if [[ $COUNT == "true" ]]; then
                echo $(date +"%m-%d-%Y_%H:%M")" Counting reads"
                awk -F$'\t' '$2 == "16" ' ./bowtie_out/${BASE}.sam | cut -f 3 | sort | uniq -c > ./count/${BASE}_counts.txt
        fi
done

# Create count table using merge_counts.py

if [[ $COUNT == "true" ]]; then
        echo $(date +"%m-%d-%Y_%H:%M")"Merging count files into count table"
        python /proj/ahmedlab/steve/seq/util/merge_counts.py ./count
fi
