# Ramka przy eksporcie z Lightroom Classic

Plugin dodaje jednolitą ramkę do eksportowanych zdjęć. Działa jako **filtr eksportu Lightroom Classic** na macOS i Windows; nie zmienia zdjęcia w katalogu ani jego ustawień Develop. Nie obsługuje Lightroom w wersji chmurowej/mobile, która nie udostępnia tego SDK.

Lightroom jest hostem, ponieważ ramka stanowi ostatni etap eksportu i można zapisać jej parametry razem z presetem. Photoshop wymagałby dodatkowego uruchamiania aplikacji lub ręcznej automatyzacji. Lightroom SDK nie udostępnia operacji dodawania pikseli do płótna, dlatego plugin korzysta z lokalnego **ImageMagick 7**.

## Instalacja

1. Zainstaluj ImageMagick 7 z <https://imagemagick.org/script/download.php>. Na macOS z Homebrew: `brew install imagemagick`. Windows: użyj instalatora ze strony ImageMagick.
2. Plugin sam wyszuka program `magick` i sprawdzi, czy jest to ImageMagick 7 — nie musisz kopiować ścieżki z terminala.
3. Zachowaj cały folder `FrameExport.lrplugin` w stałym miejscu na dysku.
4. Lightroom Classic → **File / Plik → Plug-in Manager / Menedżer dodatków → Add / Dodaj** → wybierz ten folder.
5. Otwórz **Export / Eksportuj**. W obszarze **Post-Process Actions / Działania po przetworzeniu** dodaj filtr **Ramka przy eksporcie**. Pole ścieżki zostaw puste (tryb automatyczny); poniżej zobaczysz wynik wykrywania.
6. Wybierz eksport **JPEG** lub **TIFF**, ustaw procent i kolor, następnie eksportuj. Kliknięcie próbki koloru otwiera natywny picker Lightrooma. Obok możesz wpisać dokładny kod HEX; oba pola są zsynchronizowane. Możesz zapisać ustawienia jako preset eksportu.

### Wykrywanie ImageMagick

Plugin szuka w `PATH` procesu Lightrooma, następnie w typowych lokalizacjach Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`), MacPorts (`/opt/local/bin`) lub folderach `ImageMagick-7*` w Windows Program Files. Weryfikuje wersję znalezionego programu. Lightroom otwarty z GUI może mieć inny PATH niż terminal, dlatego sprawdzane są również foldery instalacji.

Jeśli program zainstalowano w innym miejscu, przycisk **Wybierz…** otwiera okno wyboru pliku — bez ręcznego wklejania ścieżki. Opcjonalna ścieżka ma pierwszeństwo przed wyszukiwaniem automatycznym. **Wykryj ponownie** czyści ją i uruchamia wyszukiwanie. Przy eksporcie program jest ponownie sprawdzany, niezależnie od komunikatu w oknie. Po aktualizacji pluginu kliknij **Wykryj ponownie**, jeśli stary preset zawiera przykładową ścieżkę z poprzedniej wersji.

Nie umieszczaj kolejnego filtra zmieniającego wymiary po tym filtrze. Najpierw testuj na eksporcie do nowego folderu. Dla Windows ścieżki do programu i eksportu nie mogą zawierać `"`, `%` lub `!` — plugin odrzuca je z powodu interpretacji przez powłokę systemową.

## Znaczenie parametrów

- **Przyrost szerokości (%)**: łączny przyrost szerokości płótna, liczony względem szerokości wyeksportowanego zdjęcia, po połowie z lewej i prawej. **Ta sama grubość w pikselach jest stosowana u góry i u dołu**, niezależnie od proporcji zdjęcia. Jest tylko jeden parametr grubości.
- **Kolor**: natywny picker lub zapis szesnastkowy `#RRGGBB`, np. `#FFFFFF`, `#000000`, `#E8DCC8`. Wartości są interpretowane w przestrzeni kolorów eksportu; dla przewidywalnego użycia kolorów ekranowych wybierz sRGB. Ramka jest nieprzezroczysta.
- Zakres procentu: 0–200; ułamki wpisuj z kropką. Grubość krawędzi jest zaokrąglana do najbliższego pełnego piksela. Bardzo mały procent może dać zero pikseli. Procent równy zero pozostawia eksport bez ponownego kodowania i nie wymaga ImageMagick.

Przykład: zdjęcie **4000 × 3000**, przyrost szerokości **10%** → ramka **200 px na każdej krawędzi**, wynik **4400 × 3400**. Aby uzyskać ramkę 100 px wokół takiego zdjęcia, wpisz 5%.

Wzór: `grubość = round(szerokość zdjęcia × procent / 200)`. Wersja 1.1 zachowuje dotychczasowe znaczenie procentu szerokości i ustawienie z presetów; wcześniejszy procent wysokości jest ignorowany. Po aktualizacji warto zapisać preset ponownie.

Procenty odnoszą się do pliku **po kadrowaniu i skalowaniu Lightrooma**. Ramka zwiększa jego końcowe wymiary ponad limit ustawiony w Image Sizing. Znak wodny i wyostrzanie Lightrooma są wykonane przed dodaniem ramki; znak wodny pozostaje na zdjęciu, nie na ramce.

## Formaty, jakość i bezpieczeństwo plików

JPEG jest ponownie kodowany z jakością ustawioną w eksporcie Lightrooma; to dodatkowy etap stratny. Limit rozmiaru JPEG w KB nie jest gwarantowany po dodaniu ramki. Gdy zależy Ci na jakości, eksportuj TIFF: plugin zapisuje go z bezstratną kompresją ZIP, zachowując głębię obrazu. Profile ICC i metadane są przekazywane przez ImageMagick, ale nietypowe metadane należy sprawdzić na własnych plikach; nie gwarantujemy identyczności wszystkich pól.

PSD, DNG i Original nie są obsługiwane. Plugin zgłasza błąd eksportu zamiast pozostawić pozornie poprawny wynik bez ramki. Błędy ImageMagick są przekazywane do Lightrooma. Wynik powstaje w pliku tymczasowym obok eksportu; dopiero udane przetwarzanie zastępuje eksport. Przy błędzie podmiany plugin próbuje przywrócić oryginał eksportu; jeżeli to niemożliwe, komunikat wskazuje zachowaną kopię. Wymagane są uprawnienia zapisu w folderze eksportu i miejsce na plik wynikowy oraz kopię eksportu.

## Weryfikacja

W środowisku Linux z ImageMagick 7 i LuaTeX:

```sh
cd /workspace/ttt
luatex --luaonly tests/run.lua
```

Testy uruchamiają prawdziwy ImageMagick, sprawdzają równą grubość wszystkich krawędzi zdjęć poziomych i pionowych, kolor ramki, zachowanie pikseli TIFF 16-bit, JPEG, zerowy procent, błędy i przywracanie pliku. Wykrywanie programu w PATH jest testowane na Linuxie; lokalizacje Windows/macOS i dwukierunkowe wiązanie pickera z HEX są sprawdzane z symulowanym SDK. Lightroom Classic i Windows nie zostały uruchomione w tym środowisku.

Przed regularnym użyciem przetestuj w Lightroom Classic automatyczne wykrywanie ImageMagick, wybór koloru, zapis/odczyt presetu oraz eksport zdjęcia poziomego i pionowego w JPEG i TIFF. Sprawdź wynikowe wymiary, profil ICC, metadane i pozycję znaku wodnego. To konieczny test integracji z rzeczywistym hostem, którego nie zastępują testy Linux.
