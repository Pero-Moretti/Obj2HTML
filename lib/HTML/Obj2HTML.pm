package HTML::Obj2HTML;
use Carp;
use HTML::Entities;
use Text::Markdown;
use Text::Pluralize;
use Locale::Currency::Format;
use List::MoreUtils qw(uniq);
use Module::Pluggable require => 1;

use constant {
  END_TAG_OPTIONAL => 0x0,
  END_TAG_REQUIRED => 0x1,
  END_TAG_FORBIDDEN => 0x2,
  OBSOLETE => 0x4
};

# storage is a sort of top-level stash for an object. It doesn't have to be used
# you can get away with building your own object variable and passing it to "gen"
my $storage = [];
# Opts are simple storage that could be referred to in extensions (not typically
# in the base class). A good example is "readonly" (true/false)
my %opt;
# extensions are stored here
my %extensions = ();
# snippets are stored here
my $snippets = {};
# A dictionary of substitutions are stored here and can be referenced in _content_
my %dictionary;

# Whether or not to close empty tags with /
my $mode = "XHTML";
# Whether or not to output a warning when something that doesn't look like a valid
# html 5 tag is used
my $warn_on_unknown_tag = 1;
# Whether or not to use HTML::FromArrayref format ("elementname {attributes} content" triplets)
my $html_fromarrayref_format = 0;
# Default currency to use
my $default_currency = "GBP";

# Load up the extensions
plugins();

sub import {
  my %opts = @_;
  # Look in _components to register other components
  if ($opts{components}) {
    foreach my $file (split("\n", `find $opts{components} -name "*.po"`)) {
      chomp($file);
      my $l = $file;
      $l =~ s/$opts{components}\///;
      $l =~ s/\.po$//;
      $l =~ s/\//::/g;
      #print STDERR "HTML::Obj2HTML registering component $l\n";
      HTML::Obj2HTML::register_extension($l, {
        tag => "",
        before => sub {
          my $o = shift;
          if (ref $o eq "HASH") {
            return HTML::Obj2HTML::fetch($file, $o);
          } else {
            return HTML::Obj2HTML::fetch($file, { _ => $o });
          }
        }
      });
    }
  }
  if ($opts{"default_currency"}) {
    $default_currency = $opts{"default_currency"};
  }
  if ($opts{mode}) {
    $mode = $opts{mode};
  }
  if ($opts{"warn_on_unknown_tag"}) {
    $warn_on_unknown_tag = $opts{"warn_on_unknown_tag"};
  }
  if ($opts{"html_fromarrayref_format"}) {
    $html_fromarrayref_format = $opts{"html_fromarrayref_format"};
  }
}

my %tags = (
  a => END_TAG_REQUIRED,
  abbr => END_TAG_REQUIRED,
  acronym => END_TAG_REQUIRED | OBSOLETE,
  address => END_TAG_REQUIRED,
  applet => END_TAG_REQUIRED | OBSOLETE,
  area => END_TAG_FORBIDDEN,
  article => END_TAG_REQUIRED,
  aside => END_TAG_REQUIRED,
  audio => END_TAG_REQUIRED,
  b => END_TAG_REQUIRED,
  base => END_TAG_FORBIDDEN,
  basefont => END_TAG_FORBIDDEN | OBSOLETE,
  bdi => END_TAG_REQUIRED,
  bdo => END_TAG_REQUIRED,
  big => END_TAG_REQUIRED | OBSOLETE,
  blockquote => END_TAG_REQUIRED,
  body => END_TAG_OPTIONAL,
  br => END_TAG_FORBIDDEN,
  button => END_TAG_REQUIRED,
  canvas => END_TAG_REQUIRED,
  caption => END_TAG_REQUIRED,
  center => END_TAG_REQUIRED,
  cite => END_TAG_REQUIRED,
  code => END_TAG_REQUIRED,
  col => END_TAG_FORBIDDEN,
  colgroup => END_TAG_REQUIRED,
  data => END_TAG_REQUIRED,
  datalist => END_TAG_REQUIRED,
  dd => END_TAG_OPTIONAL,
  del => END_TAG_REQUIRED,
  details => END_TAG_REQUIRED,
  dfn => END_TAG_REQUIRED,
  dialog => END_TAG_REQUIRED,
  dir => END_TAG_REQUIRED | OBSOLETE,
  div => END_TAG_REQUIRED,
  dl => END_TAG_REQUIRED,
  dt => END_TAG_OPTIONAL,
  em => END_TAG_REQUIRED,
  embed => END_TAG_FORBIDDEN,
  fielset => END_TAG_REQUIRED,
  figcaption => END_TAG_REQUIRED,
  figure => END_TAG_REQUIRED,
  font => END_TAG_REQUIRED | OBSOLETE,
  footer => END_TAG_REQUIRED,
  form => END_TAG_REQUIRED,
  frame => END_TAG_FORBIDDEN | OBSOLETE,
  frameset => END_TAG_REQUIRED | OBSOLETE,
  head => END_TAG_OPTIONAL,
  header => END_TAG_REQUIRED,
  hgroup => END_TAG_REQUIRED,
  h1 => END_TAG_REQUIRED,
  h2 => END_TAG_REQUIRED,
  h3 => END_TAG_REQUIRED,
  h4 => END_TAG_REQUIRED,
  h5 => END_TAG_REQUIRED,
  h6 => END_TAG_REQUIRED,
  hr => END_TAG_FORBIDDEN,
  html => END_TAG_OPTIONAL,
  i => END_TAG_REQUIRED,
  iframe => END_TAG_REQUIRED,
  img => END_TAG_FORBIDDEN,
  input => END_TAG_FORBIDDEN,
  ins => END_TAG_REQUIRED,
  kbd => END_TAG_REQUIRED,
  keygen => END_TAG_FORBIDDEN,
  label => END_TAG_REQUIRED,
  legend => END_TAG_REQUIRED,
  li => END_TAG_REQUIRED,
  link => END_TAG_FORBIDDEN,
  main => END_TAG_REQUIRED,
  map => END_TAG_REQUIRED,
  mark => END_TAG_REQUIRED,
  menu => END_TAG_REQUIRED,
  menuitem => END_TAG_FORBIDDEN,
  meta => END_TAG_FORBIDDEN,
  meter => END_TAG_REQUIRED,
  nav => END_TAG_REQUIRED,
  noframes => END_TAG_REQUIRED | OBSOLETE,
  noscript => END_TAG_REQUIRED,
  object => END_TAG_REQUIRED,
  ol => END_TAG_REQUIRED,
  optgroup => END_TAG_REQUIRED,
  option => END_TAG_OPTIONAL,
  output => END_TAG_REQUIRED,
  p => END_TAG_OPTIONAL,
  param => END_TAG_FORBIDDEN,
  picture => END_TAG_REQUIRED,
  pre => END_TAG_REQUIRED,
  progress => END_TAG_REQUIRED,
  q => END_TAG_REQUIRED,
  rp => END_TAG_REQUIRED,
  rt => END_TAG_REQUIRED,
  ruby => END_TAG_REQUIRED,
  s => END_TAG_REQUIRED,
  samp => END_TAG_REQUIRED,
  script => END_TAG_REQUIRED,
  section => END_TAG_REQUIRED,
  select => END_TAG_REQUIRED,
  small => END_TAG_REQUIRED,
  source => END_TAG_FORBIDDEN,
  span => END_TAG_REQUIRED,
  strike => END_TAG_REQUIRED | OBSOLETE,
  strong => END_TAG_REQUIRED,
  style => END_TAG_REQUIRED,
  sub => END_TAG_REQUIRED,
  summary => END_TAG_REQUIRED,
  sup => END_TAG_REQUIRED,
  svp => END_TAG_REQUIRED,
  table => END_TAG_REQUIRED,
  tbody => END_TAG_REQUIRED,
  td => END_TAG_REQUIRED,
  template => END_TAG_REQUIRED,
  textarea => END_TAG_REQUIRED,
  tfoot => END_TAG_REQUIRED,
  th => END_TAG_OPTIONAL,
  thead => END_TAG_REQUIRED,
  time => END_TAG_REQUIRED,
  title => END_TAG_REQUIRED,
  tr => END_TAG_OPTIONAL,
  track => END_TAG_FORBIDDEN,
  tt => END_TAG_REQUIRED | OBSOLETE,
  u => END_TAG_REQUIRED,
  ul => END_TAG_REQUIRED,
  var => END_TAG_REQUIRED,
  video => END_TAG_REQUIRED,
  wbr => END_TAG_FORBIDDEN
);

sub set_opt {
  my $key = shift;
  my $val = shift;
  $opt{$key} = $val;
}
sub get_opt {
  my $key = shift;
  return $opt{$key};
}

sub set_dictionary {
  my $hashref = shift;
  %dictionary = %{$hashref};
}
sub add_dictionary_items {
  my $hashref = shift;
  %dictionary = (%dictionary, %{$hashref});
}

sub set_snippet {
  my $name = shift;
  my $obj = shift;
  if (!ref $obj) {
    my $args = shift;
    $obj = fetch($obj, $args);
  }
  $snippets->{$name} = $obj;
}
sub get_snippet {
  my $name = shift;
  return $snippets->{$name};
}




sub do {
  HTML::Obj2HTML::print($storage);
}

sub init {
  $storage = shift;
}

sub sort {
  my $parentblock = shift;
  my $sortsub = shift;
  my $arr = shift;
  my @ret = ();

  foreach my $c (sort { $sortsub->($a,$b) } @$arr) {
    push(@ret, $parentblock, $c);
  }
  return \@ret;
}

sub iterate {
  my $parentblock = shift;
  my $arr = shift;
  my $collapsearrayrefs = shift || 0;
  my @ret = ();

  foreach my $c (@$arr) {
    if (ref($c) eq "ARRAY" && $collapsearrayrefs) {
      my $itr = iterate($parentblock, $c);
      push(@ret, @{$itr});
    } elsif (defined $c) {
      push(@ret, $parentblock, $c);
    }
  }
  return \@ret;
}

sub fetchraw {
  my $f = shift;
  # If we want an absolute path, use document root
  if ($f =~ /\//) {
    $f = $ENV{DOCUMENT_ROOT}.$f;
  }
  # And don't allow back-tracking through the file system!
  $f =~ s|\/[\.\/]+|\/|;
  my $rawfile;
  if (-e $f) {
    local($/);
    open(RAWFILE, $f);
    $raw = <RAWFILE>;
    close(RAWFILE);
  }
  return $raw;
}
sub fetch {
  my $f = shift;
  our $args = shift;
  my $fetch;
  if ($f !~ /^[\.\/]/) { $f = "./".$f; }
  if (-e $f) {
    $fetch = do($f);
    if (!$fetch) {
      if ($@) {
        carp "Do failed for $f at error: $@\n";
      }
      if ($!) {
        carp "Do failed for $f bang error: $!\n";
      }
    }
  } else {
    my $pwd = `pwd`;
    chomp($pwd);
    carp "Couldn't find $f ($pwd)\n";
    return [];
  }
  return $fetch;
}
sub display {
  my $f = shift;
  my $args = shift;
  my $ret = fetch($f, $args);
  print gen($ret);
}
sub push {
  my $arr = shift;
  my $f = shift;
  my $arg = shift;
  my $ret = fetch($f,$arg);
  push(@{$arr}, @{$ret});
}
sub append {
  my $insertpoint = shift;
  my $inserto = shift;
  my $args = shift;
  if (!ref $inserto && $inserto =~ /staticfile:(.*)/) {
    $insertto = HTML::Obj2HTML::fetchraw($1);
  } elsif (!ref $inserto && $inserto =~ /file:(.*)/) {
    $inserto = fetch($1, $args);
  }
  my $o = find($storage, $insertpoint);
  foreach my $e (@{$o}) {
    # convert to common format
    if (!ref $e->[1]) {
      $e->[1] = { _ => [ _ => $e->[1] ] };
    } elsif (ref $e->[1] eq "ARRAY") {
      $e->[1] = { _ => $e->[1] };
    }
    push(@{$e->[1]->{_}}, @{$inserto});
  }
}
sub prepend {
  my $insertpoint = shift;
  my $inserto = shift;
  my $args = shift;
  if (!ref $inserto && $inserto =~ /staticfile:(.*)/) {
    $insertto = HTML::Obj2HTML::fetchraw($1);
  } elsif (!ref $inserto && $inserto =~ /file:(.*)/) {
    $inserto = fetch($1, $args);
  }
  my $o = find($storage, $insertpoint);
  foreach my $e (@{$o}) {
    # convert to common format
    if (!ref $e->[1]) {
      $e->[1] = { _ => [ _ => $e->[1] ] };
    } elsif (ref $e->[1] eq "ARRAY") {
      $e->[1] = { _ => $e->[1] };
    }
    unshift(@{$e->[1]->{_}}, @{$inserto});
  }
}

sub find {
  my $o = shift;
  my $query = shift;
  my $ret = shift || [];

  my @tags = @{$o};
  while (@tags) {
    my $tag = shift(@tags);
    my $attr = shift(@tags);

    if (ref $attr eq "ARRAY") {
      find($attr, $query, $ret);
    } elsif (ref $attr eq "HASH") {
      my %attrs = %{$attr};
      my $content;
      if ($attrs{_}) {
        find($attrs{_}, $query, $ret);
      }
      if ($query =~ /\#(.*)/ && $attrs{id} eq $1) {
        push(@{$ret}, [$tag, $attr]);
      } elsif ($query =~ /^([^\#\.]\S*)/ && $tag eq $1) {
        push(@{$ret}, [$tag, $attr]);
      }
    }
  }
  return $ret;
}

sub gen {
  my $o = shift;
  my $ret = "";

  if (!ref $o) {
    $o = web_escape($o);
    return $o;
  }
  if (ref $o eq "HASH") {
    carp "HTML::Obj2HTML::gen called with a hash reference!";
    return "";
  }
  if (ref $o eq "CODE") {
    eval {
      $ret = HTML::Obj2HTML::gen($o->());
    };
    if ($@) { carp "Error parsing HTML::Obj2HTML objects when calling code ref: $@\n"; }
    return $ret;
  }
  if (ref $o ne "ARRAY") {
    return "";
  }

  my @tags = @{$o};
  while (@tags) {
    my $tag = shift(@tags);
    if (!defined $tag) {
      next;
    }
    if (ref $tag eq "ARRAY") {
      $ret .= HTML::Obj2HTML::gen($tag);
      next;
    }
    if (ref $tag eq "CODE") {
      eval {
        $ret .= HTML::Obj2HTML::gen($tag->());
      };
      if ($@) { carp "Error parsing HTML::Obj2HTML objects when calling code ref: $@\n"; }
      next;
    }
    if ($tag =~ /_(.+)/) {
      $ret .= HTML::Obj2HTML::gen(get_snippet($1));
      next;
    }
    # If the tag has a space it's not a valid tag, so output it as content instead
    if ($tag =~ /\s/) {
      $ret .= $tag;
      next;
    }

    my $attr = shift(@tags);
    if ($html_fromarrayref_format) {
      # Make this module behave more like HTML::FromArrayref, where you have elementname, { attributes }, content
      # This should be considered for backward compatibility; The find routine would struggle with this...
      if (ref $attr eq "HASH" && ($tags{$tag} & END_TAG_FORBIDDEN) == 0) {
        $attr->{"_"} = shift(@tags);
      }
    }
    # Typically linking to another file will return an arrayref, but could equally return a hashref to also set the
    # attributes of the element calling it
    if (!ref $attr && $attr =~ /staticfile:(.+)/) {
      $attr = HTML::Obj2HTML::fetchraw($1);
    } elsif (!ref $attr && $attr =~ /file:(.+)/) {
      $attr = HTML::Obj2HTML::fetch($1);
    } elsif (!ref $attr && $attr =~ /raw:(.+)/) {
      $attr = HTML::Obj2HTML::fetchraw($1);
    }

    # Run the current tag through extentions
    my $origtag = $tag;
    if (defined $extensions{$origtag}) {
      if (defined $extensions{$origtag}->{scalarattr} && !ref $attr) { $attr = { $extensions{$origtag}->{scalarattr} => $attr }; }

      if (defined $extensions{$origtag}->{before}) {
        my $o = $extensions{$origtag}->{before}($attr);
        if (ref $o eq "ARRAY") {
          $ret .= HTML::Obj2HTML::gen($o);
        } elsif (ref $o eq "") {
          $ret .= $o;
        }
      }

      if (defined $extensions{$origtag}->{tag}) {
        $tag = $extensions{$origtag}->{tag};
      }
      if (defined $extensions{$origtag}->{attr}) {
        if (ref $attr ne "HASH") {
          $attr = { _ => $attr };
        }
        foreach my $k (keys %{$extensions{$origtag}->{attr}}) {
          if (defined $attr->{$k}) {
            $attr->{$k} = $extensions{$origtag}->{attr}->{$k}." ".$attr->{$k};
            if ($k eq "class") {
              $attr->{$k} = join(" ", uniq(split(/\s+/, $attr->{$k})));
            }
          } else {
            $attr->{$k} = $extensions{$origtag}->{attr}->{$k};
          }
        }
      }

      if (defined $extensions{$origtag}->{replace}) {
        my $o = HTML::Obj2HTML::gen($extensions{$origtag}->{replace}($attr));
        if (ref $o eq "HASH") {
          $ret .= HTML::Obj2HTML::gen($o);
        } elsif (ref $o eq "") {
          $ret .= $o;
        }
        $tag = "";
      }
    }

# Non-HTML functions
    if ($tag eq "_") {
      if (ref $attr) {
        carp("HTML::Obj2HTML: _ element called, but attr wasn't a scalar.");
      } else {
        $ret .= web_escape($attr);
      }

    } elsif ($tag eq "raw") {
      if (ref $attr) {
        carp("HTML::Obj2HTML: raw element called, but attr wasn't a scalar.");
      } else {
        $ret .= "$attr";
      }

    } elsif ($tag eq "if") {
      if (ref $attr eq "HASH") {
        if ($attr->{cond} && $attr->{true}) {
          $ret .= HTML::Obj2HTML::gen($attr->{true});
        } elsif (!$attr->{cond} && $attr->{false}) {
          $ret .= HTML::Obj2HTML::gen($attr->{false});
        }
      } elsif (ref $attr eq "ARRAY") {
        for (my $i = 0; $i<$#{$attr}; $i+=2) {
          if ($attr->[$i]) {
            $ret .= HTML::Obj2HTML::gen($attr->[$i+1]);
            last;
          }
        }
      } else {
        carp("HTML::Obj2HTML: if element called, but attr wasn't a hash ref or array ref.");
      }
    } elsif ($tag eq "switch") {
      if (ref $attr eq "HASH") {
        if (defined $attr->{$attr->{val}}) {
          $ret .= HTML::Obj2HTML::gen($attr->{$attr->{val}});
        } elsif (defined $attr->{"_default"}) {
          $ret .= HTML::Obj2HTML::gen($attr->{"_default"});
        } elsif (defined $attr->{"_"}) {
          $ret .= HTML::Obj2HTML::gen($attr->{"_"});
        }
      } else {
        carp("HTML::Obj2HTML: switch element called, but attr wasn't a hash ref.");
      }

    } elsif ($tag eq "md") {
      if (ref $attr) {
        carp("HTML::Obj2HTML: md element called, but attr wasn't a scalar.");
      } else {
        $ret .= markdown($attr);
      }

    } elsif ($tag eq "plain") {
      if (ref $attr) {
        carp("HTML::Obj2HTML: plain element called, but attr wasn't a scalar.");
      } else {
        $ret .= plain($attr);
      }

    } elsif ($tag eq "currency") {
      if (ref $attr eq "HASH") {
        $ret .= web_escape(currency_format($attr->{currency} || $default_currency, $attr->{"_"}, FMT_SYMBOL));
      } elsif (!ref $attr) {
        $ret .= web_escape(currency_format($default_currency, $attr, FMT_SYMBOL));
      } else {
        carp("HTML::Obj2HTML: currency called, but attr wasn't a hash ref or plain scalar.");
      }

    } elsif ($tag eq "pluralize") {
      if (ref $attr eq "HASH") {
        $ret .= pluralize($attr->[0], $attr->[1]);
      } else {
        carp("HTML::Obj2HTML: pluralize called, but attr wasn't a hash ref");
      }

    } elsif ($tag eq "include") {
      $ret .= HTML::Obj2HTML::gen(HTML::Obj2HTML::fetch($components.$o->{src}.".po", $attr));

    } elsif ($tag eq "javascript") {
      $ret .= "<script language='javascript' type='text/javascript' defer='1'><!--\n$attr\n//--></script>";

    } elsif ($tag eq "includejs") {
      $ret .= "<script language='javascript' type='text/javascript' defer='1' src='$attr'></script>";

    } elsif ($tag eq "doctype") {
      $ret .= "<!DOCTYPE $attr>";

    } elsif (ref $attr eq "HASH" && defined $attr->{removeif} && $attr->{removeif}) {
      $ret .= HTML::Obj2HTML::gen($attr->{_});

    # Finally through all the non-HTML elements ;)
    } elsif ($tag) {

      # It's perfectly allowed to omit content from a tag where the end tag was forbidden
      # If we have content, we have to assume that it should appear after the
      # tag - not discard it, or show it within
      # If we've got a hash ref though, we have attributes :)
      # Note that this has to go here, because the attribute might have been a staticfile: or similar
      # to execute some additional code
      if ($tags{$tag} & END_TAG_FORBIDDEN && ref $attr ne "HASH") {
        unshift(@tags, $attr);
        $attr = undef;
      }

      if ($warn_on_unknown_tag && !defined $tags{$tag}) {
        carp "Warning: Unknown tag $tag in HTML::Obj2HTML\n";
      }

      $ret .= "<$tag";
      if (!defined $attr) {
        if ($tags{$tag} & END_TAG_FORBIDDEN) {
          if ($mode eq "XHTML") {
            $ret .= " />";
          } else {
            $ret .= ">";
          }
        } elsif ($tags{$tag} & END_TAG_REQUIRED) {
          $ret .= "></$tag>";
        }

      } elsif (ref $attr eq "ARRAY") {
        $ret .= ">";
        $ret .= HTML::Obj2HTML::gen($attr);
        $ret .= "</$tag>";

      } elsif (ref $attr eq "HASH") {
        my %attrs = %{$attr};
        my $content;
        foreach my $k (keys(%attrs)) {
          if (ref $k eq "ARRAY") {
            $content = $k;
          } elsif (ref $attrs{$k} eq "ARRAY") {
            # shorthand, you can defined the content within the classname, e.g. div => { "ui segment" => [ _ => "Content" ] }
            if ($k ne "_") {
              $ret .= format_attr("class", $k);
            }
            $content = $attrs{$k} || '';

          } elsif (ref $attrs{$k} eq "HASH") {
            if (defined $attrs{$k}->{if}) {
              if ($attrs{$k}->{if} && defined $attrs{$k}->{true}) {
                $ret .= format_attr($k, $attrs{$k}->{true});
              } elsif (!$attrs{$k}->{if} && defined $attrs{$k}->{false}) {
                $ret .= format_attr($k, $attrs{$k}->{false});
              }
            }
          } elsif ($k eq "_") {
            $content = $attrs{$k} || '';

          } elsif ($k eq "if") {
            my $val = $attrs{$k};
            if ($val->{cond} && $val->{true}) {
              foreach my $newk (keys(%{$val->{true}})) {
                $ret .= " $newk=\"".web_escape($val->{true}->{newk})."\"";
              }
            } elsif ($val->{false}) {
              foreach my $newk (keys(%{$val->{false}})) {
                $ret .= " $newk=\"".web_escape($val->{false}->{newk})."\"";
              }
            }
          } else {
            $ret .= format_attr($k, $attrs{$k});
          }
        }
        if ($tags{$tag} & END_TAG_FORBIDDEN) {
          # content is also forbidden!
          if ($mode eq "XHTML") {
            $ret .= " />";
          } else {
            $ret .= ">";
          }
        } elsif (defined $content) {
          $ret .= ">";
          $ret .= HTML::Obj2HTML::gen($content);
          $ret .= "</$tag>";
        } elsif ($tags{$tag} & END_TAG_REQUIRED) {
          $ret .= "></$tag>";
        } else {
          if ($mode eq "XHTML") {
            $ret .= " />";
          } else {
            $ret .= ">";
          }
        }
      } elsif (ref $attr eq "CODE") {
        $ret .= ">";
        eval {
          $ret .= gen($attr->());
        };
        $ret .= "</$tag>";
        if ($@) { warn "Error parsing HTML::Obj2HTML objects when calling code ref: $@\n"; }
      } elsif (ref $attr eq "") {
        my $val = web_escape($attr);
        $ret .= ">$val</$tag>";
      }
    }

    if (defined $extensions{$origtag} && defined $extensions{$origtag}->{after}) {
      $ret .= $extensions{$origtag}->{after}($attr);
    }

  }
  return $ret;
}

sub format_attr {
  my $k = shift;
  my $val = shift;
  $val = web_escape($val);
  if (defined $val) {
    return " $k=\"$val\"";
  }
  return "";
}
sub substitute_dictionary {
  my $val = shift;
  $val =~ s/%([A-Za-z0-9]+)%/$dictionary{$1}/g;
  return $val;
}
sub web_escape {
  my $val = shift;
  $val = HTML::Entities::encode($val);
  $val = substitute_dictionary($val);
  return $val;
}
sub plain {
  my $txt = shift;
  $txt = web_escape($txt);
  $txt =~ s|\n|<br />|g;
  return $txt;
}
sub markdown {
  my $txt = shift;
  $txt = substitute_dictionary($txt);
  my $m = new Text::Markdown;
  $val = $m->markdown($txt);
  return $val;
}

sub print {
  my $o = shift;
  print gen($o);
}

sub format {
  my $plain = shift;
  $plain =~ s/\n/<br \/>/g;
  return [ raw => $plain ];
}

sub register_extension {
  my $tag = shift;
  my $def = shift;
  my $flags = shift;
  $extensions{$tag} = $def;
  if (defined $flags) {
    $tags{$tag} = $flags;
  } else {
    $tags{$tag} = END_TAG_OPTIONAL;
  }
}

1;
__END__

=pod

=head1 WHY?

1. Providing a more extensible way of parsing a perl objects into HTML objects,
including being able to create framework specific "plugins" that broaden what
you can do

2. Providing the option to provide the content from within an attributes hash.
This simplifies parsing and allows you to do something like:

    div => { class => "segment", _ => "Some text" }

    div => { segment => [ "Some text" ] }

But you can tell this module to use the HTML::FromArrayref syntax, in which case
you would need to do:

    div => { class => "segment" }, "Some text"

This module is also aware of tags that should not have an end tag; you don't
need to provide anything more than the element name

   p => [ "My first paragraph", br, "The next line" ]

But you can of course still provide attributes:

    hr => { class => "ui seperator" }

3. Providing extensions via plugins

Using HTML::Obj2HTML::register_extension you can define your own element and how it
should be treated. It can be a simple substitution:

    HTML::Obj2HTML::register_extension("line", {
        tag => "hr",
        attr => { class => "ui seperator" }
    });

Therefore:

    line => { class => "red" }

Would yield:

    <hr class='ui seperator red' />

Or you can define "before" and "after" subreoutines to be executed, which can
return larger pieces of rat HTML or an HTML::Obj2HTML object to be processed.

4. Providing components. Via a plugin you can also create full compents in files
that are execute as perl scripts. These can return HTML::Obj2HTML objects to be
further processed.

All in all, this looks a feels a bit like React, but for Perl (and with vastly
different syntax).

=head1 SEE ALSO

Previous attempts to do this same sort of thing:

HTML::LoL (last updated 2002)
HTML::FromArrayref (last updated 2013)
XML::FromArrayref (last updated 2013)

How this is used in Dancer:

Dancer2::Template::HTML::Obj2HTML

And a different way of routing based on the presence of files, which are
processed as HTML::Obj2HTML objects if they return an arrayref.

Dancer2::Plugin::DoFile

=end
