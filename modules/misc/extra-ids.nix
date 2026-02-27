{ ... }: {
  config = {
    ids.uids = { daemon = 390; };

    ids.gids = {
      daemon = 390;
      audit = 391;
      operator = 392;
      u2f = 116;
      _shadow = 65;
      _video = 44;
    };
  };
}
