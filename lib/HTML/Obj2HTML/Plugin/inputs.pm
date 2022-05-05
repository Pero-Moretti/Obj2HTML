HTML::Obj2HTML::register_extension("dateinput", {
  tag => "",
  before => sub {
    my $o = shift;
    return Obj2HTML::gen([
      div => { class => "ui calendar dateonly", _ => [
        div => { class => "ui input left icon", _ => [
          i => { class => "calendar icon", _ => [] },
          input => $o
        ]}
      ]}
    ]);
  }
});

1;
