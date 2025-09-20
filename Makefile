all:
	corral run -- ponyc -Dopenssl_3.0.x dependapony/ 
	./dependapony1
