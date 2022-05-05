HTML::Obj2HTML::register_extension("helplabel", {
  tag => "label",
  before => sub {
    my $o = shift;
    $o->{_} = [ _ => $o->{label} ];
    if ($o->{helptext}) {
      push(@{$o->{_}}, help => { text => $o->{helptext} });
    }
    if ($o->{helphtml}) {
      push(@{$o->{_}}, help => { html => $o->{helphtml} });
    }
    delete($o->{label});
    delete($o->{helptext});
    delete($o->{helphtml});
    return "";
  }
});
HTML::Obj2HTML::register_extension("help", {
  tag => "i",
  attr => {
    class => "blue circular icon help",
    style => "margin-left: 5px"
  },
  before => sub {
    my $o = shift;
    if ($o->{html}) {
      $o->{"data-html"} = $o->{html}; delete($o->{html});
    }
    if ($o->{text}) {
      $o->{"data-content"} = $o->{text}; delete($o->{text});
    }
    return "";
  }
});

1;
