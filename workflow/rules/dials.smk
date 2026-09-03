CONDA_ENV = "/Users/steve/micromamba/envs/mdx2"
STRIP_ABSPATH_SCRIPT = workflow.source_path("../scripts/strip_abspath.sh")
DIALS_INTEGRATE_SCRIPT = workflow.source_path("../scripts/dials_integrate_bounded.py")

rule dials_import:
    input:
        "results/datasets/{dataset}/image_files.txt"
    output: 
        expt="results/datasets/{dataset}/imported.expt",
        log="results/datasets/{dataset}/dials.import.log"
    log:
        stdout="logs/datasets/{dataset}/dials.import.stdout",
        stderr="logs/datasets/{dataset}/dials.import.stderr"
    params:
        import_args=lookup(within=config, dpath="datasets/{dataset}/dials/import", default=[]),
        image_range=lookup(within=config, dpath="datasets/{dataset}/image_range"),
    conda: CONDA_ENV
    shell: 
        """
        {{ 
        dials.import $(head -n 1 {input:q}) \
            {params.import_args:q} \
            image_range={params.image_range[0]},{params.image_range[1]} \
            output.experiments={output.expt:q} \
            output.log={output.log:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.expt:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.log:q}
        }} > {log.stdout:q} 2> {log.stderr:q}
        """

rule dials_find_spots:
    input:
        expt=rules.dials_import.output.expt
    output:
        refl="results/datasets/{dataset}/strong.refl",
        log="results/datasets/{dataset}/dials.find_spots.log"
    log:
        stdout="logs/datasets/{dataset}/dials.find_spots.stdout",
        stderr="logs/datasets/{dataset}/dials.find_spots.stderr"
    conda: CONDA_ENV
    params:
        find_spots_args=lookup(within=config, dpath="datasets/{dataset}/dials/find_spots", default=[])
    threads: 16
    shell:
        """
        dials.find_spots {input.expt:q} \
            {params.find_spots_args:q} \
            nproc={threads} \
            output.reflections={output.refl:q} \
            output.log={output.log:q} \
            > {log.stdout:q} 2> {log.stderr:q}
        """

def known_space_group(wildcards):
    space_group = (
        config["datasets"][wildcards.dataset]
        .get("crystal", {})
        .get("space_group")
    )
    return (
        f"known_symmetry.space_group={space_group}"
        if space_group is not None
        else ""
    )

rule dials_index:
    input:
        expt=rules.dials_import.output.expt,
        refl=rules.dials_find_spots.output.refl
    output:
        expt="results/datasets/{dataset}/indexed.expt",
        refl="results/datasets/{dataset}/indexed.refl",
        log="results/datasets/{dataset}/dials.index.log"
    log:
        stdout="logs/datasets/{dataset}/dials.index.stdout",
        stderr="logs/datasets/{dataset}/dials.index.stderr",
    conda: CONDA_ENV
    params:
        index_args=lookup(within=config, dpath="datasets/{dataset}/dials/index", default=[]),
        space_group=known_space_group,
    shell:
        """
        {{
        dials.index {input.expt:q} {input.refl:q} \
            {params.index_args:q} \
            {params.space_group:q} \
            nproc={threads} \
            output.experiments={output.expt:q} \
            output.reflections={output.refl:q} \
            output.log={output.log:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.expt:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.log:q}
        }} > {log.stdout:q} 2> {log.stderr:q}
        """

rule dials_refine:
    input:
        expt=rules.dials_index.output.expt,
        refl=rules.dials_index.output.refl
    output:
        expt="results/datasets/{dataset}/refined.expt",
        refl="results/datasets/{dataset}/refined.refl",
        log="results/datasets/{dataset}/dials.refine.log"
    log:
        stdout="logs/datasets/{dataset}/dials.refine.stdout",
        stderr="logs/datasets/{dataset}/dials.refine.stderr"
    conda: CONDA_ENV
    params:
        refine_args=lookup(within=config, dpath="datasets/{dataset}/dials/refine", default=[]),
    shell:
        """
        {{
        dials.refine {input.expt:q} {input.refl:q} \
            {params.refine_args:q} \
            nproc={threads} \
            output.experiments={output.expt:q} \
            output.reflections={output.refl:q} \
            output.log={output.log:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.expt:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.log:q}
        }} > {log.stdout:q} 2> {log.stderr:q}
        """

rule dials_integrate:
    input:
        expt=rules.dials_refine.output.expt,
        refl=rules.dials_refine.output.refl
    output:
        expt="results/datasets/{dataset}/integrated.expt",
        refl="results/datasets/{dataset}/integrated.refl",
        log="results/datasets/{dataset}/dials.integrate.log",
        phil=temporary("results/datasets/{dataset}/dials.integrate.phil")
    log:
        stdout="logs/datasets/{dataset}/dials.integrate.stdout",
        stderr="logs/datasets/{dataset}/dials.integrate.stderr"
    conda: CONDA_ENV
    params:
        integrate_args=lookup(within=config, dpath="datasets/{dataset}/dials/integrate", default=[]),
    threads: 16
    resources:
        mem_mb=16000
    shell:
        """
        {{
        python {DIALS_INTEGRATE_SCRIPT} {resources.mem_mb} \
            {input.expt:q} {input.refl:q} \
            {params.integrate_args:q} \
            nproc={threads} \
            output.experiments={output.expt:q} \
            output.reflections={output.refl:q} \
            output.log={output.log:q} \
            output.phil={output.phil:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.expt:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.log:q}
        }} > {log.stdout:q} 2> {log.stderr:q}
        """

def dials_scale_resolution_limit(wildcards):
    # return dmin=<value> if resolution is specified, otherwise ""
    resolution = (
        config["datasets"][wildcards.dataset]
        .get("crystal", {})
        .get("resolution")
    )
    return f"d_min={resolution}" if resolution is not None else ""

rule dials_scale:
    input:
        expt=rules.dials_integrate.output.expt,
        refl=rules.dials_integrate.output.refl
    output:
        expt="results/datasets/{dataset}/scaled.expt",
        refl="results/datasets/{dataset}/scaled.refl",
        log="results/datasets/{dataset}/dials.scale.log",
        html=report(
            "results/datasets/{dataset}/dials.scale.html",
            category="dials",
            labels={
                "dataset": "{dataset}",
                "step": "dials.scale"
            }
        )
    log:
        stdout="logs/datasets/{dataset}/dials.scale.stdout",
        stderr="logs/datasets/{dataset}/dials.scale.stderr"
    conda: CONDA_ENV
    params:
        scale_args=lookup(within=config, dpath="datasets/{dataset}/dials/scale", default=[]),
        resolution=dials_scale_resolution_limit,
    shell:
        """
        {{
        dials.scale {input.expt:q} {input.refl:q} \
            {params.scale_args:q} \
            {params.resolution:q} \
            nproc={threads} \
            output.experiments={output.expt:q} \
            output.reflections={output.refl:q} \
            output.log={output.log:q} \
            output.html={output.html:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.expt:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.log:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.html:q}
        }} > {log.stdout:q} 2> {log.stderr:q}
        """

rule dials_reindex:
    input:
        expt=rules.dials_scale.output.expt,
        refl=rules.dials_scale.output.refl, 
        reference=lookup(within=config, dpath="datasets/{dataset}/crystal/reference_pdb_file")
    output:
        expt="results/datasets/{dataset}/reindexed.expt",
        refl="results/datasets/{dataset}/reindexed.refl",
        log="results/datasets/{dataset}/dials.reindex.log"
    log:
        stdout="logs/datasets/{dataset}/dials.reindex.stdout",
        stderr="logs/datasets/{dataset}/dials.reindex.stderr"
    conda: CONDA_ENV
    params:
        reindex_args=lookup(within=config, dpath="datasets/{dataset}/dials/reindex", default=[]),
    shell:
        """
        {{
        dials.reindex {input.expt:q} {input.refl:q} \
            {params.reindex_args:q} \
            reference.file={input.reference:q} \
            output.experiments={output.expt:q} \
            output.reflections={output.refl:q} \
            output.log={output.log:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.expt:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.log:q}
        }} > {log.stdout:q} 2> {log.stderr:q}
        """


rule dials_slice_sequence:
    input:
        expt="results/datasets/{dataset}/{stage}.expt",
        refl="results/datasets/{dataset}/{stage}.refl"
    output:
        expt="results/datasets/{dataset}/{subset}/{stage}.expt",
        refl="results/datasets/{dataset}/{subset}/{stage}.refl"
    log:
        stdout="logs/datasets/{dataset}/{subset}/dials.slice_sequence.{stage}.stdout", 
        stderr="logs/datasets/{dataset}/{subset}/dials.slice_sequence.{stage}.stderr"
    conda: CONDA_ENV
    params:
        image_range=lookup(within=config, dpath="datasets/{dataset}/subsets/{subset}/image_range"),
    shell:
        """
        {{
        dials.slice_sequence {input.expt:q} {input.refl:q} \
            output.experiments_filename={output.expt:q} \
            output.reflections_filename={output.refl:q} \
            image_range={params.image_range[0]},{params.image_range[1]}
        bash {STRIP_ABSPATH_SCRIPT} {output.expt:q}
        }} > {log.stdout:q} 2> {log.stderr:q}
        """

def processing_group_inputs(wildcards):
    # return a dict {'expt': [...], 'refl': [...]} of input experiments and reflections for a processing group
    members = config["processing_groups"][wildcards.group]["members"]

    reference_pdb_file = config["processing_groups"][wildcards.group].get("crystal", {}).get("reference_pdb_file")

    experiments = []
    reflections = []
    # if dataset/crystal/reference_pdb_file exists, used reindexed.expt and reindexed.refl. 
    # otherwise, assume no indexing ambiguity and use scaled.expt and scaled.refl.

    filename = 'reindexed' if reference_pdb_file is not None else 'scaled'
    for member in members:
        dataset = member["dataset"]
        subset = member.get("subset")
        if subset is not None:
            experiments.append(f"results/datasets/{dataset}/{subset}/{filename}.expt")
            reflections.append(f"results/datasets/{dataset}/{subset}/{filename}.refl")
        else:
            experiments.append(f"results/datasets/{dataset}/{filename}.expt")
            reflections.append(f"results/datasets/{dataset}/{filename}.refl")
    return {"expt": experiments, "refl": reflections}

def dials_scale_group_resolution_limit(wildcards):
    # return dmin=<value> if resolution is specified, otherwise ""
    resolution = (
        config["processing_groups"][wildcards.group]
        .get("crystal", {})
        .get("resolution")
    )
    return f"d_min={resolution}" if resolution is not None else ""

rule dials_scale_group:
    input:
        unpack(processing_group_inputs)
    output:
        expt="results/processing_groups/{group}/scaled.expt",
        refl="results/processing_groups/{group}/scaled.refl",
        log="results/processing_groups/{group}/dials.scale.log",
        html=report(
            "results/processing_groups/{group}/dials.scale.html",
            category="dials",
            labels={
                "group": "{group}",
                "step": "dials.scale"
            }
        )
    log:
        stdout="logs/processing_groups/{group}/dials.scale.stdout",
        stderr="logs/processing_groups/{group}/dials.scale.stderr"
    conda: CONDA_ENV
    params:
        scale_args=lookup(within=config, dpath="processing_groups/{group}/dials/scale", default=[]),
        resolution_limit=dials_scale_group_resolution_limit,
    shell:
        """
        {{
        dials.scale {input.expt:q} {input.refl:q} \
            {params.scale_args:q} \
            {params.resolution_limit} \
            nproc={threads} \
            output.experiments={output.expt:q} \
            output.reflections={output.refl:q} \
            output.log={output.log:q} \
            output.html={output.html:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.expt:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.log:q}
        bash {STRIP_ABSPATH_SCRIPT} {output.html:q}
        }} > {log.stdout:q} 2> {log.stderr:q}
        """