package FAlite;
use strict;
sub new {
	my ($class, $fh) = @_;
	if (ref $fh !~ /GLOB/)
		{die ref $fh, "\n", "FAlite ERROR: expect a GLOB reference\n"}
	my $this = bless {};
	$this->{FH} = $fh;
	while(<$fh>) {last if $_ =~ /\S/} # not supposed to have blanks, but...
	my $firstline = $_;
	if (not defined $firstline) {warn "FAlite: Empty\n"; return $this}
	if ($firstline !~ /^>/) {warn "FAlite: Not FASTA formatted\n"; return $this}
	$this->{LASTLINE} = $firstline;
	chomp $this->{LASTLINE};
	return $this;
}
sub nextEntry {
	my ($this) = @_;
	return 0 if not defined $this->{LASTLINE};
	my $fh = $this->{FH};
	my $def = $this->{LASTLINE};
	my @seq;
	my $lines_read = 0;
	while(<$fh>) {
		$lines_read++;
		if ($_ =~ /^>/) {
			$this->{LASTLINE} = $_;
			chomp $this->{LASTLINE};
			last;
		}
		push @seq, $_;
	}
	return 0 if $lines_read == 0;
	chomp @seq;
	my $entry = FAlite::Entry::new($def, \@seq);
	return $entry;
}

package FAlite::Entry;
use overload '""' => 'all';
sub new {
	my ($def, $seqarry) = @_;
	my $this = bless {};
	$this->{DEF} = $def;
	$this->{SEQ} = join("", @$seqarry);
	$this->{SEQ} =~ s/\s//g; # just in case more spaces
	return $this;
}
sub def {shift->{DEF}}
sub seq {shift->{SEQ}}
sub all {my $e = shift; return $e->{DEF}."\n".$e->{SEQ}."\n"}

1;

__END__

=head1 NAME

FAlite;

=head1 SYNOPSIS

 use FAlite;
 my $fasta = new FAlite(\*STDIN);
 while(my $entry = $fasta->nextEntry) {
     $entry->def;
     $entry->seq;
 }

=head1 DESCRIPTION

FAlite is a package for parsing FASTA files and databases. The FASTA format is
widely used in bioinformatics. It consists of a definition line followed by
sequence with an arbitrary number of lines and line lengths.

A FASTA file looks like this:

 >identifier descriptive text
 GAATTC

A FASTA database looks like this:

 >identifier1 some text describing this entry
 GAATTC
 ACTAGT
 >identifier2 some text describing this entry
 AAACCT
 GCTAAT

=head2 Object

FAlite has two kinds of objects, the file and the entry.

 my $fasta_file = new FAlite(\*STDIN); # or any other filehandle
 $entry = $fasta_file->nextEntry; # single fasta fle
 while(my $entry = $fasta_file->nextEntry) {
     # canonical form of use for fasta database
 }

The entry has two attributes (def and seq).

 $entry->def; # access the def line
 $entry->seq; # access the sequence
 "$entry";    # overload to fasta file ($entry->def . "\n" . $entry->seq)

=head1 AUTHOR

Ian Korf (ikorf@sapiens.wustl.edu, http://sapiens.wustl.edu/~ikorf)

=head1 ACKNOWLEDGEMENTS

This software was developed at the Genome Sequencing Center at Washington
Univeristy, St. Louis, MO.

=head1 COPYRIGHT

Copyright (C) 1999 Ian Korf. All Rights Reserved.

=head1 DISCLAIMER

This software is provided "as is" without warranty of any kind.

=cut







