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
        description = "Enable proxycontainers";
      };
      rootDomain = mkOption {
        type = types.str;
        description =
          ''
          Root domain for the host. Navigating to this domain will display a list
          of available sites hosted inside the host.
          '';
        example = "example.com";
      };
      containers = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            ip = mkOption {
              type = types.str;
              description =
                ''
                Private network IP for the container.
                This will be automatically allocation if not provided.
                '';
            };
            port = mkOption {
              description = "Port inside the container that external traffic will be forwarded to";
              type = types.str;
              default = "80";
            };
            config = mkOption {
              description = "Nix configuration for the container";
              # type = types.attrs; # TODO validate configs as submodules
              default = {};
            };
          };
        });
        description = "Container definitions for containers hosted on the target machine";
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
            <footer>Powered By:
              <a href="https://github.com/kylesferrazza/proxycontainers">
                ProxyContainers
              </a>
            </footer>
          '')}/home/";
          enableACME = true;
          forceSSL = true;
        };
      };
    };
  });
}
