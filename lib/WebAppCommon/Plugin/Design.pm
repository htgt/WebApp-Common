package WebAppCommon::Plugin::Design;

use strict;
use warnings FATAL => 'all';

use Moose::Role;
use Hash::MoreUtils qw( slice slice_def );
use List::Util qw( max min );
use List::MoreUtils qw( uniq );
use namespace::autoclean;
use WebAppCommon::Util::Sanitize qw( sanitize_like_expr );

requires qw( schema check_params throw retrieve log trace );

has _design_comment_category_ids => (
    isa         => 'HashRef',
    traits      => [ 'Hash' ],
    lazy_build  => 1,
    handles     => {
        design_comment_category_id_for => 'get'
    }
);

sub _build__design_comment_category_ids {
    my $self = shift;

    my %category_id_for = map { $_->name => $_->id }
        $self->schema->resultset( 'DesignCommentCategory' )->all;

    return \%category_id_for;
}

sub c_list_design_types {
    my $self = shift;

    my $rs = $self->schema->resultset( 'DesignType' )->search( {}, { order_by => { -asc => 'id' } } );

    return [ map { $_->id } $rs->all ];
}

sub pspec_create_design {
    return {
        species                   => { validate => 'existing_species', rename => 'species_id' },
        id                        => { validate => 'integer', optional => 1 },
        type                      => { validate => 'existing_design_type', rename => 'design_type_id' },
        created_at                => { validate => 'date_time', post_filter => 'parse_date_time', optional => 1 },
        created_by                => { validate => 'existing_user', post_filter => 'user_id_for' },
        phase                     => { validate => 'phase', optional => 1 },
        validated_by_annotation   => { validate => 'validated_by_annotation', default => 'not done' },
        name                      => { validate => 'alphanumeric_string', optional => 1 },
        target_transcript         => { optional => 1, validate => 'ensembl_transcript_id' },
        oligos                    => { optional => 1 },
        comments                  => { optional => 1 },
        genotyping_primers        => { optional => 1 },
        gene_ids                  => { optional => 1 },
        design_parameters         => { validate => 'json', optional => 1 },
        cassette_first            => { validate => 'boolean', default => 1 },
        global_arm_shortened      => { validate => 'integer', optional => 1 },
        nonsense_design_crispr_id => { validate => 'integer', optional => 1 },
        parent_id                 => { optional => 1 },
        hdr_template              => { validate => 'dna_seq', optional => 1 },
    };
}

sub pspec_create_design_comment {
    return {
        category       =>  { validate    => 'existing_design_comment_category',
                             post_filter => 'design_comment_category_id_for',
                             rename      => 'design_comment_category_id' },
        comment_text   => { optional => 1 },
        created_at     => { validate => 'date_time', post_filter => 'parse_date_time', optional => 1 },
        created_by     => { validate => 'existing_user', post_filter => 'user_id_for' },
        is_public      => { validate => 'boolean', default => 0 }
    }
}

sub pspec_create_genotyping_primer {
    return {
        type          => { validate => 'existing_genotyping_primer_type', rename => 'genotyping_primer_type_id' },
        seq           => { validate => 'dna_seq' },
        id            => { validate => 'integer', optional => 1 },
        design_id     => { validate => 'integer', optional => 1 },
        tm            => { optional => 1 },
        gc_content    => { optional => 1 },
        is_validated  => { validate => 'boolean', optional => 1 },
        is_rejected   => { validate => 'boolean', optional => 1 },
    }
}

sub c_create_design {
    my ( $self, $params ) = @_;
    my $validated_params = $self->check_params( $params, $self->pspec_create_design );

    my $design_match = existing_design_check($self, $validated_params);
    if ($design_match) {
        my $existing_design = $self->schema->resultset('Design')->find({ id => $design_match });

        my $response = $existing_design->type->id . " design with those oligos already exists: $design_match";
        $self->log->debug( $response );
        $existing_design->{user_response} = $response;

        return $existing_design;
    }

    my $design = $self->schema->resultset( 'Design' )->create(
        {
            slice_def( $validated_params,
                       qw( id species_id name created_by created_at design_type_id
                           phase validated_by_annotation target_transcript
                           design_parameters cassette_first global_arm_shortened
                           nonsense_design_crispr_id parent_id
                          )
                      )
        }
    );
    $self->log->debug( 'Create design ' . $design->id );
    for my $g ( @{ $validated_params->{gene_ids} || [] } ) {
        $self->trace( "Create gene_design " . $g->{gene_id} );
        $design->create_related(
            genes => {
                gene_id      => $g->{gene_id},
                gene_type_id => $g->{gene_type_id},
                created_by   => $self->user_id_for('unknown')
            }
        );
    }

    for my $c ( @{ $validated_params->{comments} || [] } ) {
        $self->trace( "Create design comment", $c );
        my $validated = $self->check_params( $c, $self->pspec_create_design_comment );
        $design->create_related( comments => $validated );
    }

    for my $oligo_params ( @{ $validated_params->{oligos} || [] } ) {
        $oligo_params->{design_id} = $design->id;
        $self->c_create_design_oligo( $oligo_params, $design );
    }

    for my $p ( @{ $validated_params->{genotyping_primers} || [] } ) {
        $self->trace( "Create genotyping primer", $p );
        my $validated = $self->check_params( $p, $self->pspec_create_genotyping_primer );
        $design->create_related( genotyping_primers => $validated );
    }

    #Match design types in the Miseq family
    if ( $design->type->id =~ /^miseq\-\S+$/ ) {
        $self->trace("Creating WT Amplicon for Design: " . $design->id);
        _design_amplicons($self, $design, $validated_params);

        if ( $design->type->id eq 'miseq-hdr' && $params->{hdr_template} ) {
            $self->trace("Creating HDR Amplicon for Design: " . $design->id);
            _design_amplicons($self, $design, $validated_params, $params->{hdr_template});
        }
    }

    return $design;
}

sub _design_amplicons {
    my ($self, $design, $params, $hdr) = @_;

    my $locus;
    my $seq = $design->amplicon;
    my $type = 'WT';

    if ($hdr) {
        $seq = $hdr;
        $type = 'HDR';

        my @oligos = @{$design->oligos_sorted};
        #[Left external, Left internal, Right Internal, Right External] 

        my $chr_id = $self->schema->resultset('Chromosome')->find({
            species_id => $oligos[1]->{locus}->{species},
            name => $oligos[1]->{locus}->{chr_name}
        })->id;

        $locus = {
            assembly_id => $oligos[1]->{locus}->{assembly},
            chr_id      => $chr_id,
            chr_start   => $oligos[1]->{locus}->{chr_start},
            chr_end     => $oligos[2]->{locus}->{chr_end} + 1,
            chr_strand  => $oligos[1]->{locus}->{chr_strand},
        };
    };

    $self->create_amplicon({
        design_id => $design->id,
        seq => $seq,
        amplicon_type => $type,
        locus => $locus,
    });

    return;
}

sub pspec_create_design_oligo {
    return {
        type      => { validate => 'existing_design_oligo_type', rename => 'design_oligo_type_id' },
        seq       => { validate => 'dna_seq' },
        loci      => { optional => 1 },
        design_id => { validate => 'integer' },
    };
}

sub c_create_design_oligo {
    my ( $self, $params, $design ) = @_;
    my $validated_params = $self->check_params( $params, $self->pspec_create_design_oligo );
    $self->trace( "Create design oligo", $validated_params );
    $design ||= $self->c_retrieve_design( { id => $validated_params->{design_id} } );
    delete $validated_params->{design_id};
    my $loci = delete $validated_params->{loci};
    my $oligo = $design->create_related( oligos => $validated_params );

    for my $locus_params ( @{ $loci || [] } ) {
        $locus_params->{design_id} = $design->id;
        $locus_params->{oligo_type} = $oligo->design_oligo_type_id;
        $self->c_create_design_oligo_locus( $locus_params, $oligo );
    }

    return $oligo;
}

sub pspec_create_design_oligo_locus {
    return {
        assembly   => { validate => 'existing_assembly' },
        chr_name   => { validate => 'existing_chromosome' },
        chr_start  => { validate => 'integer' },
        chr_end    => { validate => 'integer' },
        chr_strand => { validate => 'strand' },
        oligo_type => { validate => 'existing_design_oligo_type' },
        design_id  => { validate => 'integer' },
        species    => { validate => 'existing_species', optional => 1 },
    };
}

sub c_create_design_oligo_locus {
    my ( $self, $params, $oligo ) = @_;
    my $validated_params = $self->check_params( $params, $self->pspec_create_design_oligo_locus );
    $self->trace( "Create oligo locus", $validated_params );

    $oligo ||= $self->c_retrieve_design_oligo(
        {
            design_id  => $validated_params->{design_id},
            oligo_type => $validated_params->{oligo_type},
        }
    );

    $oligo->design->species->check_assembly_belongs( $validated_params->{assembly} );

    my $oligo_locus = $oligo->create_related(
        loci => {
            assembly_id => $validated_params->{assembly},
            chr_id      => $self->_chr_id_for( @{$validated_params}{ 'assembly', 'chr_name' } ),
            chr_start   => $validated_params->{chr_start},
            chr_end     => $validated_params->{chr_end},
            chr_strand  => $validated_params->{chr_strand}
        }
    );

    return $oligo_locus;
}

sub existing_design_check {
    my ($self, $params ) = @_;

    my @starts = map { $_->{loci}[0]->{chr_start} } @{$params->{oligos}};
    my @ends = map { $_->{loci}[0]->{chr_end} } @{$params->{oligos}};

    my $oligos = $self->schema->resultset('DesignOligoLocus')->search({
        chr_start => \@starts,
        chr_end => \@ends,
    }, {
        join => 'design_oligo',
    });

    my $existing_design_loci;
    while ( my $oligo = $oligos->next ) {
        my $oligo_design_id = $oligo->design_oligo->design_id;
        my $design_hash = $oligo->design_oligo->as_hash;
        $design_hash->{type} = $oligo->design_oligo->design->type->id;
        $design_hash->{hdr} = $oligo->design_oligo->design->hdr_amplicon // '';
        push ( @{ $existing_design_loci->{$oligo_design_id} }, $design_hash );
    }

    my $match;
    foreach my $existing_design (keys %{ $existing_design_loci }) {
        my $oligo_count = int scalar @{ $existing_design_loci->{$existing_design} };
        my $existing_design_type = $existing_design_loci->{$existing_design}[0]->{type};
        my $intended_design_type = $params->{design_type_id};
        my $existing_hdr = $existing_design_loci->{$existing_design}[0]->{hdr};
        my $intended_hdr = $params->{hdr_template};

        if ( $intended_design_type eq $existing_design_type && $oligo_count == 4 ) {
            if ( ! $intended_hdr || $intended_hdr eq $existing_hdr ) {
                $match = $existing_design;
            }
        }
    }

    return $match;
}

sub pspec_delete_design {
    return {
        id      => { validate => 'integer' },
        cascade => { validate => 'boolean', optional => 1 }
    }
}

sub c_delete_design {
    my ( $self, $params ) = @_;

    my $validated_params = $self->check_params( $params, $self->pspec_delete_design );

    my %search = slice( $validated_params, 'id' );
    my $design = $self->schema->resultset( 'Design' )->find( \%search )
        or $self->throw(
            NotFound => {
                entity_class  => 'Design',
                search_params => \%search
            }
        );

    # Check that design is not assigned to a gene
    if ( $design->genes_rs->count > 0 ) {
        $self->throw( InvalidState => 'Design ' . $design->id . ' has been assigned to one or more genes' );
    }

    # # Check that design is not allocated to a process and, if it is, refuse to delete
    if ( $design->process_designs_rs->count > 0 ) {
        $self->throw( InvalidState => 'Design ' . $design->id . ' has been used in one or more processes' );
    }

    if ( $validated_params->{cascade} ) {
        $design->comments_rs->delete;
        $design->genotyping_primers_rs->delete;
        for my $oligo ( $design->oligos_rs->all ) {
            $oligo->loci_rs->delete;
            $oligo->delete;
        }
    }

    $design->delete;

    return 1;
}

sub pspec_retrieve_design {
    return {
        id      => { validate => 'integer' },
        species => { validate => 'existing_species', rename => 'species_id', optional => 1 }
    };
}

sub c_retrieve_design {
    my ( $self, $params ) = @_;
    my $validated_params = $self->check_params( $params, $self->pspec_retrieve_design );

    my $design = $self->retrieve( Design => { slice_def $validated_params, qw( id species_id ) } );

    return $design;
}

sub pspec_retrieve_design_oligo {
    return {
        id         => { validate => 'integer', optional => 1 },
        design_id  => { validate => 'integer', optional => 1 },
        oligo_type => {
            validate => 'existing_design_oligo_type',
            rename   => 'design_oligo_type_id',
            optional => 1
        },
        REQUIRE_SOME => { design_id_or_design_oligo_id => [ 1, qw( id design_id ) ] },
        DEPENDENCY_GROUPS => { design_id_and_oligo_type => [qw( design_id oligo_type )] },
    };
}

sub c_retrieve_design_oligo {
    my ( $self, $params ) = @_;
    my $validated_params = $self->check_params( $params, $self->pspec_retrieve_design_oligo );

    my $design_oligo = $self->retrieve(
        DesignOligo => { slice_def $validated_params, qw( design_id design_oligo_type_id id ) } );

    return $design_oligo;
}

sub pspec_list_assigned_designs_for_gene {
    return {
        gene_id   => { validate => 'non_empty_string' },
        species   => { validate => 'existing_species', rename => 'species_id' },
        type      => { validate => 'existing_design_type', optional => 1 },
        gene_type => { validate => 'existing_gene_type', optional => 1 },
    }
}

#fetch all designs from the GeneDesign table for a given mgi accession id
sub c_list_assigned_designs_for_gene {
    my ( $self, $params ) = @_;

    my $validated_params = $self->check_params( $params, $self->pspec_list_assigned_designs_for_gene );

    my %search = (
        'me.species_id' => $validated_params->{species_id},
        'genes.gene_id' => $validated_params->{gene_id}
    );

    if ( defined $validated_params->{type} ) {
        $search{'me.design_type_id'} = $validated_params->{type};
    }

    # can optionally search just amoungst a specific gene id type ( e.g. MGI ID or HGNC ID )
    if ( defined $validated_params->{gene_type} ) {
        $search{'genes.gene_type_id'} = $validated_params->{gene_type};
    }

    #genes is the GeneDesign table
    my $design_rs = $self->schema->resultset('Design')->search( \%search, { join => 'genes' } );

    return [ $design_rs->all ];
}

sub pspec_list_candidate_designs_for_gene {
    return {
        gene_id => { validate => 'non_empty_string' },
        species => { validate => 'existing_species', rename => 'species_id' },
        type    => { validate => 'existing_design_type', optional => 1 }
    }
}

#find any potential designs by checking if any of the loci overlap with a gene
sub c_list_candidate_designs_for_gene {
    my ( $self, $params ) = @_;

    my $validated_params = $self->check_params( $params, $self->pspec_list_candidate_designs_for_gene );

    my ( $chr, $start, $end, $strand ) = $self->_get_gene_chr_start_end_strand( $validated_params->{species_id}, $validated_params->{gene_id} );

    my %search = (
        'default_locus.species_id' => $validated_params->{species_id},
        'default_locus.chr_name'   => $chr,
        'default_locus.chr_strand' => $strand,
    );

    if ( $strand == 1 ) {
        $search{'default_locus.u5_end'}   = { '<', $end };
        $search{'default_locus.d3_start'} = { '>', $start };
    }
    else {
        $search{'default_locus.d3_end'}   = { '<', $end };
        $search{'default_locus.u5_start'} = { '>', $start };
    }

    if ( defined $validated_params->{type} ) {
        $search{'me.design_type_id'} = $validated_params->{type};
    }

    my $design_rs = $self->schema->resultset('Design')->search( \%search, { join => 'default_locus' } );

    return [ $design_rs->all ];
}

sub pspec_search_gene_designs {
    return {
        search_term => { validate => 'non_empty_string' },
        species     => { validate => 'existing_species' },
        page        => { validate => 'integer', optional => 1, default => 1 },
        pagesize    => { validate => 'integer', optional => 1, default => 50 },
        gene_type   => { validate => 'existing_gene_type', optional => 1 },
    };
}

#this function expects a marker symbol (or partial one), and returns any matching results
#from the GeneDesigns table.
sub c_search_gene_designs {
    my ( $self, $params ) = @_;

    my $validated_params = $self->check_params( $params, $self->pspec_search_gene_designs );

    my %search = (
        gene_id             => { ilike => sanitize_like_expr( $validated_params->{ search_term } ) . "%" },
        'design.species_id' => $validated_params->{species},
    );

    # can optionally search just amoungst a specific gene id type ( e.g. MGI ID or HGNC ID )
    if ( defined $validated_params->{gene_type} ) {
        $search{gene_type_id} = $validated_params->{gene_type};
    }

    #find all gene_ids like the search term
    my $gene_designs = $self->schema->resultset( 'GeneDesign' )->search(
        \%search,
        {
            join     => 'design',
            page     => $validated_params->{ page },
            rows     => $validated_params->{ pagesize },
        }
    );

    #get lists of designs, matching the format from list_designs in BrowseDesigns.pm
    my @designs;
    for my $gene_design ( $gene_designs->all ) {
        #we need to preserve the correct (naturally sorted) order, and no longer need groupings
        push @designs, { gene_id => $gene_design->gene_id, designs => [ $gene_design->design->as_hash(0) ] };
    }

    return ( \@designs, $gene_designs->pager );
}

sub pspec_create_design_target {
    return {
        species              => { validate => 'existing_species', rename => 'species_id' },
        gene_id              => { validate => 'non_empty_string', optional => 1 },
        marker_symbol        => { validate => 'non_empty_string', optional => 1 },
        ensembl_gene_id      => { validate => 'non_empty_string' },
        ensembl_exon_id      => { validate => 'non_empty_string' },
        exon_size            => { validate => 'integer', optional => 1 },
        exon_rank            => { validate => 'integer', optional => 1 },
        canonical_transcript => { validate => 'non_empty_string', optional => 1 },
        assembly             => { validate => 'existing_assembly', rename => 'assembly_id' },
        build                => { validate => 'integer', rename => 'build_id' },
        chr_name             => { validate => 'existing_chromosome' },
        chr_start            => { validate => 'integer' },
        chr_end              => { validate => 'integer' },
        chr_strand           => { validate => 'strand' },
        automatically_picked => { validate => 'boolean' },
        comment              => { optional => 1 },
    }
}

sub c_create_design_target {
    my ( $self, $params ) = @_;

    my $validated_params = $self->check_params( $params, $self->pspec_create_design_target );

    my $existing_target = $self->schema->resultset('DesignTarget')->find(
        {
            ensembl_exon_id => $validated_params->{ensembl_exon_id},
            build_id        => $validated_params->{build_id}
        }
    );

    $self->throw(
        InvalidState => 'Design target already exists on same build for exon: '
        . $validated_params->{ensembl_exon_id}
    ) if $existing_target;

    my $design_target = $self->schema->resultset( 'DesignTarget' )->create(
        {
            chr_id => $self->_chr_id_for( @{$validated_params}{ 'assembly_id', 'chr_name' } ),
            slice_def (
                $validated_params,
                qw ( species_id design_type_id gene_id marker_symbol ensembl_gene_id
                     ensembl_exon_id exon_size exon_rank canonical_transcript
                     assembly_id build_id chr_start chr_end chr_strand
                     automatically_picked comment
                   )
            ),
        }
    );
    $self->log->debug( 'Created design target ' . $design_target->id );

    return $design_target;
}

sub _get_gene_chr_start_end_strand {
    my ( $self, $species, $gene_id ) = @_;

    my @ensembl_genes = @{ $self->ensembl_gene_adaptor( $species )->fetch_all_by_external_name( $gene_id ) };

    if ( @ensembl_genes == 0 ) {
        $self->throw(
            NotFound => {
                message       => 'Found no matching EnsEMBL genes',
                entity_class  => 'EnsEMBL Gene',
                search_params => { external_id => $gene_id }
            }
        );
    }

    my @gene_chr = uniq( map { $_->seq_region_name } @ensembl_genes );
    if ( @gene_chr != 1 ) {
        $self->throw(
            InvalidState => sprintf( 'EnsEMBL genes (%s) have different chromosomes',
                                     join( q{, }, map { $_->stable_id } @ensembl_genes ) )
        );
    }

    my @gene_strand = uniq( map { $_->seq_region_strand } @ensembl_genes );
    if ( @gene_strand != 1 ) {
        $self->throw(
            InvalidState => sprintf( 'EnsEMBL genes (%s) have different strands',
                                     join( q{, }, map { $_->stable_id } @ensembl_genes ) )
        );
    }

    my $gene_start  = min( map { $_->seq_region_start } @ensembl_genes );
    my $gene_end    = max( map { $_->seq_region_end   } @ensembl_genes );

    return ( $gene_chr[0], $gene_start, $gene_end, $gene_strand[0] );
}

sub pspec_create_design_attempt {
    return {
        design_parameters => { validate => 'json', optional => 1 },
        gene_id           => { validate => 'non_empty_string' },
        status            => { validate => 'non_empty_string', optional => 1 },
        fail              => { validate => 'json', optional => 1 },
        error             => { validate => 'non_empty_string', optional => 1 },
        design_ids        => { validate => 'non_empty_string', optional => 1 },
        species           => { validate => 'existing_species', rename => 'species_id' },
        created_at        => { validate => 'date_time', post_filter => 'parse_date_time', optional => 1 },
        created_by        => { validate => 'existing_user', post_filter => 'user_id_for' },
        comment           => { optional => 1 },
        candidate_oligos  => { validate => 'json', optional => 1 },
        candidate_regions => { validate => 'json', optional => 1 },
    }
}

sub c_create_design_attempt {
    my ( $self, $params ) = @_;

    my $validated_params = $self->check_params( $params, $self->pspec_create_design_attempt );

    my $design_attempt = $self->schema->resultset( 'DesignAttempt' )->create(
        {
            slice_def (
                $validated_params,
                qw ( design_parameters gene_id status fail error species_id
                     design_ids created_at created_by comment
                     candidate_oligos candidate_regions
                   )
            )
        }
    );
    $self->log->info( 'Created design attempt ' . $design_attempt->id );

    return $design_attempt;
}

sub pspec_update_design_attempt {
    return {
        id                => { validate => 'integer' },
        design_parameters => { validate => 'json', optional => 1 },
        status            => { validate => 'non_empty_string', optional => 1 },
        fail              => { validate => 'json', optional => 1 },
        error             => { validate => 'non_empty_string', optional => 1 },
        design_ids        => { validate => 'integer', optional => 1 },
        comment           => { optional => 1 },
        candidate_oligos  => { validate => 'json', optional => 1 },
        candidate_regions => { validate => 'json', optional => 1 },
    }
}

sub c_update_design_attempt {
    my ( $self, $params ) = @_;

    my $design_attempt = $self->c_retrieve_design_attempt( $params );
    my $validated_params = $self->check_params( $params, $self->pspec_update_design_attempt );

    $design_attempt->update(
        {   slice_def $validated_params,
            qw( status fail error design_ids comment design_parameters
                candidate_oligos candidate_regions
              )
        }
    );

    return $design_attempt;
}

sub pspec_retrieve_design_attempt {
    return {
        id      => { validate => 'integer' },
        species => { validate => 'existing_species', rename => 'species_id', optional => 1 }
    };
}

sub c_retrieve_design_attempt {
    my ( $self, $params ) = @_;

    my $validated_params
        = $self->check_params( $params, $self->pspec_retrieve_design_attempt, ignore_unknown => 1 );

    return $self->retrieve( DesignAttempt => { slice_def $validated_params, qw( id species_id ) } );
}

sub c_delete_design_attempt {
    my ( $self, $params ) = @_;

    # design_attempt() will validate the parameters
    my $design_attempt = $self->c_retrieve_design_attempt($params);

    $design_attempt->delete;

    return 1;
}

sub pspec_update_design_oligo_loci {
    return {
        design_oligo_id => { validate => 'existing_design_oligo_locus' },
        assembly_id     => { validate => 'existing_assembly', optional => 1 },
        chr_strand      => { validate => 'strand', optional => 1 },
        chr_start       => { validate => 'integer', optional => 1 },
        chr_end         => { validate => 'integer', optional => 1 },
        chr_id          => { validate => 'existing_chromosome_id', optional => 1 },
    };
}

sub update_design_oligo_loci {
    my ( $self, $params ) = @_;

    my $validated_params = $self->check_params( $params, $self->pspec_update_design_oligo_loci );
    my %search = (
        'me.design_oligo_id' => $validated_params->{design_oligo_id}
    );

    my $locus = $self->retrieve( 'DesignOligoLocus' => \%search );
    my $db_record = $locus->as_hash;

    my @keys = qw(
        design_oligo_id
        assembly_id
        chr_strand
        chr_start
        chr_end
        chr_id
    );

    my $edited_row;
    foreach my $key (@keys) {
        $edited_row->{$key} = _check_undef($validated_params->{$key}, $db_record->{$key} );
    }

    $locus->update($edited_row);

    return;
}

sub _check_undef {
    my ($updated, $existing) = @_;
    if (defined $updated) {
            return $updated;
    }
    else{
        if(defined $existing) {
            return $existing;
        }
    }
    return "0";
}

1;

__END__
