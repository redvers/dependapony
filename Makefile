all:
	corral run -- ponyc -Dopenssl_3.0.x -d dependapony/ 
	./dependapony1
