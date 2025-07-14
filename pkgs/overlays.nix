final: prev: {
  openafs = prev.openafs.override {
    withTsm = true;
  };
}
