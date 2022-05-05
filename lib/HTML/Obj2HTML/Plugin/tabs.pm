package HTML::Obj2HTML::tabsection;

my @tabs = ();
my @content = ();

HTML::Obj2HTML::register_extension("tabsection", {
  tag => "",
  before => sub {
    my $obj = shift;
    @curtabs = ();
    @content = ();
    return Obj2HTML::gen($obj);
  },
  after => sub {
    my $obj = shift;
    my $divinner = {
      class => "ui tabular menu",
      _ => \@tabs
    };
    if (ref $obj eq "HASH") {
      foreach my $k (%{$obj}) {
        if (defined $divinner->{$k}) { $divinner->{$k} .= " ".$obj->{$k}; } else { $divinner->{$k} = $obj->{$k}; }
      }
      return Obj2HTML::gen([ div => $divinner, \@content ]);
    } else {
      return Obj2HTML::gen([ div => { class => "ui top attached tabular menu", _ => \@tabs }, \@content ]);
    }
  }
});
HTML::Obj2HTML::register_extension("tab", {
  tag => "",
  before => sub {
    my $obj = shift;
    if ($obj->{class}) { $obj->{class} .= " "; }
    if ($obj->{active}) { $obj->{class} .= "active "; }
    push(@tabs, div => { class => $obj->{class}."item", "data-tab" => $obj->{tab}, _ => $obj->{label} });
    push(@content, div => { class => $obj->{class}."ui bottom attached tab segment", "data-tab" => $obj->{tab}, _ => $obj->{content} });
    return "";
  }
});

1;
