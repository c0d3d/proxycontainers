{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.proxycontainers;
  startIp = 11;
  makeIp = num: "192.168.100.${toString num}";
  makeSlug = num: toString num;
  addIps = (set:
    let
      names = builtins.attrNames set;
      folded = lib.lists.foldr (cur: acc:
        let
          val = builtins.getAttr cur set;
          newVal = val // { ip = makeIp acc.idx; slug = makeSlug acc.idx; };
          newItems = acc.items // { "${cur}" = newVal; };
          newIdx = acc.idx + 1;
        in { items = newItems; idx = newIdx; }
        ) { idx = startIp; items = {}; } names;
    in folded.items
  );
  makeContainerDef = (name: value: nameValuePair "c${value.slug}" {
    inherit (value) config;
    autoStart = true;
    privateNetwork = true;
    hostAddress = "192.168.100.10";
    localAddress = "${value.ip}";
  });
in {
  options = {
    proxycontainers = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      rootDomain = mkOption {
        type = types.str;
      };
      containers = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            ip = mkOption {
              type = types.str;
            };
            port = mkOption {
              type = types.str;
              default = "80";
            };
            config = mkOption {
              # type = types.attrs; # TODO validate configs as submodules
              default = {};
            };
          };
        });
        default = {};
      };
    };
  };
  config = mkIf (cfg.enable)
  (let
    withIps = addIps cfg.containers;
  in {
    containers = mapAttrs' makeContainerDef withIps;
    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      virtualHosts = (mapAttrs (name: value: {
        enableACME = true;
        forceSSL = true;
        locations."/".proxyPass = "http://${value.ip}:${value.port}/";
      }) withIps) // {
        ${cfg.rootDomain} = {
          root = let
            names = attrNames withIps;
            listItems = map (name: "<li><a href=\"//${name}\">${name}</a></li>\n") names;
            str = builtins.concatStringsSep "" listItems;
          in "${(pkgs.writeTextDir "home/index.html" ''
            <h1>This route is not configured.</h1>
            <h2>Configured routes:</h2>
            <ul>
              ${str}
            </ul>
          '')}/home/";
          enableACME = true;
          forceSSL = true;
        };
      };
    };
  });
}
