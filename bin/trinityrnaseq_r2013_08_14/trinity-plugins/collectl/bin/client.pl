#!/usr/bin/perl -w

use IO::Socket;
use IO::Select;

if (!defined($ARGV[0]))
{
  print "usage: client.pl address[:port]\n";
  exit;
}
($address,$port)=split(/:/, $ARGV[0]);
$port=2655    if !defined($port);

$SIG{"INT"}=\&sigInt;      # for ^C

select STDOUT;
$|=1;
while (1)
{
  $socket=new IO::Socket::INET(
      PeerAddr => $address, 
      PeerPort => $port, 
      Proto    => 'tcp', 
      Timeout  =>1);

  if (!defined($socket))
  {
    print "Couldn't connect to server, retrying...\n";
    sleep 1;
    next;
  }

  print "Socket opened on $address:$port\n";
  $select = new IO::Select($socket);

  while ($socket ne '')
  {
    $buffer='';
    while (my @ready=$select->can_read(10))
    {
      $bytes=sysread($socket, $line, 100);
      #print "BYTES: $bytes\n";
      if ($bytes==0)
      {
        print "Socket closed on other end\n";
	$socket='';
        last;
      }
      $buffer.=$line;
      @handles=($select->can_read(0));
      last  if scalar(@handles)==0;
    }
    print "$buffer"    if $buffer ne '';
  }
}

sub sigInt
{
  print "Close Socket\n";
  $socket->close()     if defined($socket) && $socket ne '';
  exit;
}
