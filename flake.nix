{
	description = "A very basic flake";

	inputs.nixpkgs.url = github:NixOS/nixpkgs/da0b0bc6a5d699a8a9ffbf9e1b19e8642307062a;

	outputs = { self, nixpkgs }: 
		let
		pkgs = nixpkgs.legacyPacakges.x86_64-linux;
		in {
			devShells.x86_64-linux.default = pkgs.mkShell {
				name = "Ritsuko";

				packages = with pkgs; [
					ansible
					jmespath
					(python3.withPackages (pipy: [ pipy.jmespath ]))
				];
			};
		};
}
