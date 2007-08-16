# -*- perl -*-
package Smokeping::Slave;
use warnings;
use strict;
use Data::Dumper;
use Storable qw(nstore retrieve);
use Digest::MD5 qw(md5_base64);
use LWP::UserAgent;
use Smokeping;


=head1 NAME

Smokeping::Slave - Slave functionality for Smokeping

=head1 OVERVIEW

The Module inmplements the functionality required to run in slave mode.

=head2 IMPLEMENTATION

=head3 submit_results

In slave mode we just hit our targets and submit the results to the server.
If we can not get to the server, we submit the results in the next round.
The server in turn sends us new config information if it sees that ours is
out of date.

=cut

sub get_results;
sub get_results {
    my $slave_cfg = shift;
    my $cfg = shift;
    my $probes = shift;
    my $tree = shift;
    my $name = shift;
    my $justthisprobe = shift; # if defined, update only the targets probed by this probe
    my $probe = $tree->{probe};
    my $results = [];
    return [] unless $cfg;
    foreach my $prop (keys %{$tree}) {
        if (ref $tree->{$prop} eq 'HASH'){
            my $subres = get_results $slave_cfg, $cfg, $probes, $tree->{$prop}, $name."/$prop", $justthisprobe;
            push @{$results}, @{$subres};
        } 
        next unless defined $probe;
        next if defined $justthisprobe and $probe ne $justthisprobe;
        my $probeobj = $probes->{$probe};
        if ($prop eq 'host') {
            #print "update $name\n";
            my $updatestring = $probeobj->rrdupdate_string($tree);
            push @$results, "$name\t".time()."\t$updatestring";
        }
    }
    return $results;
}
         
sub submit_results {    
    my $slave_cfg = shift;
    my $cfg = shift;
    my $myprobe = shift;
    my $probes = shift;
    my $store = $slave_cfg->{cache_dir}."/data";
    $store .= "_$myprobe" if $myprobe;
    $store .= ".cache";
    my $restore = retrieve $store if -f $store; 
    my $data =  get_results($slave_cfg, $cfg, $probes, $cfg->{Targets}, '', $myprobe);    
    push @$data, @$restore if $restore;    
    my $data_dump = join("\n",@{$data}) || "";
    my $ua = LWP::UserAgent->new(
        agent => 'smokeping-slave/1.0',
        timeout => 10,
        env_proxy => 1 );

    my $response = $ua->post(
        $slave_cfg->{master_url},
        Content_Type => 'form-data',
        Content => [
            slave => $slave_cfg->{slave_name},
            key  => md5_base64($slave_cfg->{shared_secret}.$data_dump),
            data => $data_dump,
            config_time => $cfg->{__last} || 0,
        ],
    );
    if ($response->is_success){
        my $data = $response->content;
        my $key = $response->header('Key');
        if ($response->header('Content-Type') ne 'application/smokeping-config'){
            warn "$data\n" unless $data =~ /OK/;
            Smokeping::do_debuglog("Sent data to Server. Server said $data");
            return undef;
        };
        if (md5_base64($slave_cfg->{shared_secret}.$data) ne $key){
            warn "WARNING $slave_cfg->{master_url} sent data with wrong key";
            return undef;
        }
        my $VAR1;
        eval $data;
        if ($@){
            warn "WARNING evaluating new config from server failed: $@";
        } elsif (defined $VAR1 and ref $VAR1 eq 'HASH'){
            $VAR1->{General}{piddir} = $slave_cfg->{cache_dir};
            Smokeping::do_debuglog("Sent data to Server and got new config");
            return $VAR1;
        }                       
    } else {
        # ok did not manage to get our data to the server.
        # we store the result so that we can try again later.
        warn "WARNING Master said ".$response->status_line()."\n";
        nstore $data, $store;
    }
    return undef;
}

1;

__END__

=head1 COPYRIGHT

Copyright 2007 by Tobias Oetiker

=head1 LICENSE

This program is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the Free
Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
02139, USA.

=head1 AUTHOR

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

=cut