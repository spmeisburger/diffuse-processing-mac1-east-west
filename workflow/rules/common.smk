wildcard_constraints: 
    experiment="[^/]+",
    dataset="[^/]+"

onstart:
    print("Checking reference data and downloading if needed")
    shell("datalad get data/reference")