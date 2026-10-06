#CONDA_ENV = "/Users/steve/micromamba/envs/mdx2"
CONDA_ENV = workflow.source_path("../envs/dials_mdx2.yaml")
MDX2_EMBED_GEOMETRY_SCRIPT = workflow.source_path("../scripts/mdx2_embed_geometry.py")

# how to handle subsets?
# I could have a reserved subset key called 'all', and hard-code dials to use it.
# Or I could make mdx2 do most processing in the root folder, and extract subsets
# later for scale and merge. This might be cleaner.

def get_input_experiments(wildcards):
    # if dataset is not a background (has crystal object):
    # if dataset has crystal reference, user reindexed. otherwise use scaled.expt.
    crystal = config["datasets"][wildcards.dataset].get("crystal")
    if crystal is None:
        filename = 'masked'
    else:
        reference_pdb_file = crystal.get("reference_pdb_file")
        filename = 'reindexed' if reference_pdb_file is not None else 'scaled'
    return f"results/datasets/{wildcards.dataset}/{filename}.expt"

rule mdx2_import_geometry:
    input:
        expt=get_input_experiments
    output: 
        nxs="results/datasets/{dataset}/geometry.nxs",
        log="results/datasets/{dataset}/mdx2.import_geometry.log"
    log:
        stdout="logs/datasets/{dataset}/mdx2.import_geometry.stdout", 
        stderr="logs/datasets/{dataset}/mdx2.import_geometry.stderr"
    conda: CONDA_ENV
    shell:
        """
        mdx2.import_geometry {input.expt} \
            --outfile {output.nxs} \
            --logfile {output.log} \
            > {log.stdout:q} 2> {log.stderr:q}
        """

# version for crystal data
rule mdx2_import_data:
    input:
        expt=get_input_experiments
    output:
        nxs="results/datasets/{dataset}/data.nxs",
        datastore=directory("results/datasets/{dataset}/datastore"),
        log="results/datasets/{dataset}/mdx2.import_data.log",
    log:
        stdout="logs/datasets/{dataset}/mdx2.import_data.stdout", 
        stderr="logs/datasets/{dataset}/mdx2.import_data.stderr"
    conda: CONDA_ENV
    threads: 16
    shell:
        """
        mdx2.import_data {input.expt} \
            --datastore {output.datastore} \
            --nproc {threads} \
            --outfile {output.nxs} \
            --logfile {output.log} \
            > {log.stdout:q} 2> {log.stderr:q}
        """

# TODO: add count_threshold parameter estimator
rule mdx2_find_peaks:
    input:
        geometry=rules.mdx2_import_geometry.output.nxs,
        data=rules.mdx2_import_data.output.nxs,
        datastore=rules.mdx2_import_data.output.datastore,
    output:
        nxs="results/datasets/{dataset}/peaks.nxs",
        log="results/datasets/{dataset}/mdx2.find_peaks.log",
    log:
        stdout="logs/datasets/{dataset}/mdx2.find_peaks.stdout", 
        stderr="logs/datasets/{dataset}/mdx2.find_peaks.stderr"
    params:
        count_threshold=lookup(within=config, dpath="datasets/{dataset}/mdx2/find_peaks/count_threshold"),
    conda: CONDA_ENV
    threads: 16
    shell:
        """
        mdx2.find_peaks {input.geometry} {input.data} \
            --nproc {threads} \
            --count_threshold {params.count_threshold} \
            --outfile {output.nxs} \
            --logfile {output.log} \
            > {log.stdout:q} 2> {log.stderr:q}
        """

rule mdx2_mask_peaks:
    input:
        geometry=rules.mdx2_import_geometry.output.nxs,
        data=rules.mdx2_import_data.output.nxs,
        peaks=rules.mdx2_find_peaks.output.nxs,
    output:
        nxs="results/datasets/{dataset}/mask.nxs",
        log="results/datasets/{dataset}/mdx2.mask_peaks.log",
    log:
        stdout="logs/datasets/{dataset}/mdx2.mask_peaks.stdout", 
        stderr="logs/datasets/{dataset}/mdx2.mask_peaks.stderr"
    conda: CONDA_ENV
    threads: 16
    shell:
        """
        mdx2.mask_peaks {input.geometry} {input.data} {input.peaks} \
            --nproc {threads} \
            --outfile {output.nxs} \
            --logfile {output.log} \
            > {log.stdout:q} 2> {log.stderr:q}
        """

rule mdx2_integrate:
    input:
        geometry=rules.mdx2_import_geometry.output.nxs,
        data=rules.mdx2_import_data.output.nxs,
        mask=rules.mdx2_mask_peaks.output.nxs,
    output:
        nxs="results/datasets/{dataset}/integrated.nxs",
        log="results/datasets/{dataset}/mdx2.integrate.log",
    log:
        stdout="logs/datasets/{dataset}/mdx2.integrate.stdout", 
        stderr="logs/datasets/{dataset}/mdx2.integrate.stderr"
    conda: CONDA_ENV
    threads: 16
    params:
        subdivide=lookup(within=config, dpath="datasets/{dataset}/mdx2/integrate/subdivide"),
    shell:
        """
        mdx2.integrate {input.geometry} {input.data} \
            --mask {input.mask} \
            --subdivide {params.subdivide} \
            --nproc {threads} \
            --outfile {output.nxs} \
            --logfile {output.log} \
            > {log.stdout:q} 2> {log.stderr:q}
        """

rule mdx2_bin_image_series:
    input:
        data=rules.mdx2_import_data.output.nxs,
    output:
        nxs="results/datasets/{dataset}/binned.nxs",
        log="results/datasets/{dataset}/mdx2.bin_image_series.log",
    log:
        stdout="logs/datasets/{dataset}/mdx2.bin_image_series.stdout", 
        stderr="logs/datasets/{dataset}/mdx2.bin_image_series.stderr"
    conda: CONDA_ENV
    threads: 16
    params:
        valid_range=lookup(within=config, dpath="datasets/{dataset}/mdx2/bin_image_series/valid_range"),
        number_per_bin=lookup(within=config, dpath="datasets/{dataset}/mdx2/bin_image_series/number_per_bin"),
    shell:
        """
        mdx2.bin_image_series {input.data} \
            {params.number_per_bin} \
            --valid_range {params.valid_range} \
            --nproc {threads} \
            --outfile {output.nxs} \
            --logfile {output.log} \
            > {log.stdout:q} 2> {log.stderr:q}
        """

def lookup_background_map(wildcards):
    background_dataset = config["datasets"][wildcards.dataset].get("background_dataset")
    return f"results/datasets/{background_dataset}/binned.nxs"

rule mdx2_correct:
    input:
        geometry=rules.mdx2_import_geometry.output.nxs,
        integrated=rules.mdx2_integrate.output.nxs,
        background=lookup_background_map
    output:
        nxs="results/datasets/{dataset}/corrected.nxs",
        log="results/datasets/{dataset}/mdx2.correct.log",
    log:
        stdout="logs/datasets/{dataset}/mdx2.correct.stdout", 
        stderr="logs/datasets/{dataset}/mdx2.correct.stderr"
    conda: CONDA_ENV
    shell:
        """
        mdx2.correct {input.geometry} {input.integrated} \
            --background {input.background} \
            --outfile {output.nxs} \
            --logfile {output.log} \
            > {log.stdout:q} 2> {log.stderr:q}
        """

# TODO: is it necessary to create named (procedural) rules, or can I use generic rules with wildcards?
for pg in config["processing_groups"]:
    grp_cfg = config["processing_groups"][pg]
    members = [member['dataset'] for member in grp_cfg["members"]]
    
    corrected = [f"results/datasets/{m}/corrected.nxs" for m in members]
    scales = [f"results/processing_groups/{pg}/{m}/scales.nxs" for m in members]
    geometry = f"results/datasets/{members[0]}/geometry.nxs" # HACK geometry taken from first member only

    # TODO: add --mca2020 (omitted for now because I'm testing on small wedge data)
    # got this error in scaling detector position: mdx2.scale failed after 10.00 seconds: negative dimensions are not allowed
    rule:
        name: f"mdx2_scale_group_{pg}"
        input:
            corrected=corrected
        output:
            nxs=scales,
            log=f"results/processing_groups/{pg}/mdx2.scale.log",
            report=f"results/processing_groups/{pg}/scaling_model.ipynb",
            report_log=f"results/processing_groups/{pg}/mdx2.report.scaling_model.log",
        log:
            stdout=f"logs/processing_groups/{pg}/mdx2.scale.stdout",
            stderr=f"logs/processing_groups/{pg}/mdx2.scale.stderr",
        conda: CONDA_ENV
        shell:
            """
            {{
            mdx2.scale {input.corrected} \
                --mca2020 \
                --outfile {output.nxs} \
                --logfile {output.log}
            mdx2.report --template scaling_model -o {output.report} {output.nxs} --logfile {output.report_log}
            }} > {log.stdout:q} 2> {log.stderr:q}
            """

    rule:
        name: f"mdx2_merge_group_{pg}"
        input:
            corrected=corrected,
            scales=scales,
            geometry=geometry,
        output:
            nxs=f"results/processing_groups/{pg}/merged.nxs",
            vis_report=f"results/processing_groups/{pg}/visualization.ipynb",
            stats_report=f"results/processing_groups/{pg}/map_statistics.ipynb",
            log=f"results/processing_groups/{pg}/mdx2.merge.log",
            stats_report_log=f"results/processing_groups/{pg}/mdx2.report.map_statistics.log",
            vis_report_log=f"results/processing_groups/{pg}/mdx2.report.visualization.log",
        log:
            stdout=f"logs/processing_groups/{pg}/mdx2.merge.stdout",
            stderr=f"logs/processing_groups/{pg}/mdx2.merge.stderr",
        conda: CONDA_ENV
        shell:
            """
            {{
            mdx2.merge {input.corrected} \
                --scale {input.scales} \
                --split randomHalf \
                --outlier 5 \
                --outfile {output.nxs} \
                --logfile {output.log}
            python {MDX2_EMBED_GEOMETRY_SCRIPT} {input.geometry} {output.nxs}
            mdx2.report --template visualization {output.nxs} -o {output.vis_report} --logfile {output.vis_report_log}
            mdx2.report --template map_statistics {output.nxs} -o {output.stats_report} --logfile {output.stats_report_log}
            }} > {log.stdout:q} 2> {log.stderr:q}
            """