wildcard_constraints: 
    experiment="[^/]+",
    dataset="[^/]+"

onstart:
    print("Checking reference data and downloading if needed")
    shell("datalad get data/reference")

rule all:
    input:
        expand("results/processing_groups/{processing_group}/scaled.expt", processing_group=config["processing_groups"])

def get_dataset_filenames(wildcards):
    dataset_config = config["datasets"][wildcards.dataset]
    prefix = dataset_config["prefix"]
    image_range = dataset_config["image_range"]
    frames_per_data_file = dataset_config["frames_per_data_file"]
    data_file_template = dataset_config["data_file_template"]
    master_file_template = dataset_config.get("master_file_template", None)

    # convert from image_range to data file index range (one-based inclusive indexing)
    start_index = (image_range[0] - 1) // frames_per_data_file + 1
    end_index = (image_range[1] - 1) // frames_per_data_file + 1
    
    filenames = []
    if master_file_template is not None:
        filenames.append(master_file_template.format(prefix=prefix))
    for index in range(start_index, end_index+1):
        filenames.append(data_file_template.format(prefix=prefix, index=index))
    return filenames

rule fetch_dataset:
    output:
        temporary("results/datasets/{dataset}/image_files.txt") # always trigger fetch when images are needed, in case datalad drop is called at some point
    params:
        filenames = get_dataset_filenames
    shell:
        """
        filenames="{params.filenames}" && \
        datalad get $filenames && \
        printf '%s\n' $filenames > {output}
        """