rule filter_alignments:
    input:
        bam = cfdna_wgs_frag_bam_inputs + "/{library}.bam",
        keep_bed = config["files"]["cfdna_wgs_frag_keep_bed"],
    params:
        script = config["dir"]["scripts"]["cfdna_wgs"] + "/filter_alignments.sh",
        temp_dir = config["dir"]["data"]["cfdna_wgs"] + "/tmp",
        threads = config["threads"]["cfdna_wgs"],
    resources:
        mem_mb=5000
    output:
        cfdna_wgs_frag_filt_bams + "/{library}_filt.bam",
    container:
        config["container"]["cfdna_wgs"],
    shell:
        """
        {params.script} \
        {input.bam} \
        {input.keep_bed} \
        {params.temp_dir} \
        {params.threads} \
        {output}
        """

rule read_to_frag_bed:
    input:
        cfdna_wgs_frag_filt_bams + "/{library_id}_filt.bam",
    params:
        fasta = config["dir"]["data"]["cfdna_wgs"] + "/inputs/chr19.fa",
        script = config["dir"]["scripts"]["cfdna_wgs"] + "/read_to_frag_bed.sh",
    output:
        cfdna_wgs_frag_beds + "/{library_id}_frag.bed",
    resources:
        mem_mb=5000
    container:
        config["container"]["cfdna_wgs"]
    shell:
        """
        {params.script} \
	{input} \
        {params.fasta} \
        {output}
        """

# For each library, makes a csv with columns of library_id, gc_strata, and fract_frags
rule gc_distro:
    container:
        config["container"]["cfdna_wgs"],
    input:
        cfdna_wgs_frag_beds + "/{library_id}_frag.bed",
    log:
        cfdna_wgs_logs + "/{library_id}_gc_distro.log",
    output:
        cfdna_wgs_distros + "/{library_id}_gc_distro.csv"
    params:
        script = config["dir"]["scripts"]["cfdna_wgs"] + "/gc_distro.R",
    shell:
        """
        Rscript {params.script} \
        {input} \
        {output} \
        > {log} 2>&1
        """

# Make tibble of gc_strata and median fraction of fragments from healthy samples
rule make_healthy_gc_summary:
    container:
        config["container"]["cfdna_wgs"],
    input:
        expand(cfdna_wgs_distros + "/{library_id}_gc_distro.csv", library_id = LIBRARIES),
    log:
        cfdna_wgs_logs + "/make_healthy_gc_summary.log",
    output:
        cfdna_wgs_distros + "/healthy_med.rds"
    params:
        distro_dir = cfdna_wgs_distros,
        healthy_libs_str = LIBRARIES_HEALTHY,
        script = config["dir"]["scripts"]["cfdna_wgs"] + "/make_healthy_gc_summary.R",
    shell:
        """
        Rscript {params.script} \
        {params.distro_dir} \
        "{params.healthy_libs_str}" \
        {output} \
        > {log} 2>&1
        """

rule sample_frags_by_gc:
    container:
        config["container"]["cfdna_wgs"],
    input:
        healthy_med = cfdna_wgs_distros + "/healthy_med.rds",
        frag_bed = cfdna_wgs_frag_beds + "/{library_id}_frag.bed",
    log:
        cfdna_wgs_logs + "/{library_id}_sample_frags_by_gc.log",
    output:
        cfdna_wgs_frag_beds + "/{library_id}_frag_sampled.bed",
    params:
        script = config["dir"]["scripts"]["cfdna_wgs"] + "/sample_frags_by_gc.R",
    shell:
        """
        Rscript {params.script} \
        {input.healthy_med} \
        {input.frag_bed} \
        {output} > {log} 2>&1
        """

rule frag_window_sum:
    container:
        config["container"]["cfdna_wgs"],
    input:
        cfdna_wgs_frag_beds + "/{library_id}_frag_sampled.bed",
    log:
        cfdna_wgs_logs + "/{library_id}_frag_window_sum.log",
    output:
        short = cfdna_wgs_frag_len + "/{library_id}_norm_short.bed",
        long = cfdna_wgs_frag_len + "/{library_id}_norm_long.bed",
    params:
        script = config["dir"]["scripts"]["cfdna_wgs"] + "/frag_window_sum.sh",
    shell:
        """
        {params.script} \
        {input} \
        {output.short} \
        {output.long} &> {log}
        """

rule frag_window_int:
    input:
        short = cfdna_wgs_frag_len + "/{library_id}_norm_short.bed",
        long = cfdna_wgs_frag_len + "/{library_id}_norm_long.bed",
        matbed = "test/inputs/keep.bed",
    params:
        script = config["dir"]["scripts"]["cfdna_wgs"] + "/frag_window_int.sh",
    output:
        long = cfdna_wgs_frag_cnt + "/{library_id}_cnt_long.tmp",
        short = cfdna_wgs_frag_cnt + "/{library_id}_cnt_short.tmp",
    shell:
        """
        {params.script} \
        {input.short} \
        {input.matbed} \
        {output.short}
        {params.script} \
        {input.long} \
        {input.matbed} \
        {output.long}
        """

rule count_merge:
    input:
        expand(cfdna_wgs_frag_cnt + "/{library_id}_cnt_{len}.tmp", library_id = LIBRARIES, len = ["short", "long"]),
    output:
        config["dir"]["data"]["cfdna_wgs"] + "/frag_counts.tsv",
    params:
        script = config["dir"]["scripts"]["cfdna_wgs"] + "/count_merge.sh"
    shell:
        """
        {params.script} \
	"{input}" \
        {output}
        """
