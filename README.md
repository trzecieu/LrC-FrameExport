# Ramka przy eksporcie z Lightroom Classic

Plugin dodaje jednolitą ramkę do eksportowanych zdjęć. Działa jako **filtr eksportu Lightroom Classic** na macOS i Windows; nie zmienia zdjęcia w katalogu ani jego ustawień Develop. Nie obsługuje Lightroom w wersji chmurowej/mobile, która nie udostępnia tego SDK.

Lightroom jest hostem, ponieważ ramka stanowi ostatni etap eksportu i można zapisać jej parametry razem z presetem. Photoshop wymagałby dodatkowego uruchamiania aplikacji lub ręcznej automatyzacji. Lightroom SDK nie udostępnia operacji dodawania pikseli do płótna, dlatego plugin korzysta z lokalnego **ImageMagick 7**.

## Instalacja

1. Zainstaluj ImageMagick 7 z <https://imagemagick.org/script/download.php>. Na macOS z Homebrew: `brew install imagemagick`. Windows: użyj instalatora ze strony ImageMagick.
2. Sprawdź pełną ścieżkę do `magick`: na macOS `command -v magick`, na Windows `where magick`. W terminalu uruchom znaleziony program z `-version`.
3. Zachowaj cały folder `FrameExport.lrplugin` w stałym miejscu na dysku.
4. Lightroom Classic → **File / Plik → Plug-in Manager / Menedżer dodatków → Add / Dodaj** → wybierz ten folder.
5. Otwórz **Export / Eksportuj**. W obszarze **Post-Process Actions / Działania po przetworzeniu** dodaj filtr **Ramka przy eksporcie**. W sekcji filtra wpisz rzeczywistą pełną ścieżkę do `magick` (domyślna jest tylko przykładem).
6. Wybierz eksport **JPEG** lub **TIFF**, ustaw procenty i kolor, następnie eksportuj. Możesz zapisać ustawienia jako preset eksportu.

Nie umieszczaj kolejnego filtra zmieniającego wymiary po tym filtrze. Najpierw testuj na eksporcie do nowego folderu. Dla Windows ścieżki do programu i eksportu nie mogą zawierać `"`, `%` lub `!` — plugin odrzuca je z powodu interpretacji przez powłokę systemową.

## Znaczenie parametrów

- **Szerokość (%)**: łączny przyrost szerokości płótna, liczony względem szerokości wyeksportowanego zdjęcia, po połowie z lewej i prawej.
- **Wysokość (%)**: analogicznie, po połowie u góry i u dołu.
- **Kolor**: zapis szesnastkowy `#RRGGBB`, np. `#FFFFFF`, `#000000`, `#E8DCC8`. Wartości są interpretowane w przestrzeni kolorów eksportu; dla przewidywalnego użycia kolorów ekranowych wybierz sRGB.
- Zakres procentów: 0–200; ułamki wpisuj z kropką. Każda krawędź jest zaokrąglana do najbliższego pełnego piksela. Bardzo mały procent może dać zero pikseli. Oba parametry równe zero pozostawiają eksport bez ponownego kodowania.

Przykład: zdjęcie **4000 × 3000**, szerokość **10%**, wysokość **20%** → lewa/prawa ramka **200 px**, górna/dolna **300 px**, wynik **4400 × 3600**. Równe procenty przy prostokątnym zdjęciu dają różne grubości w pikselach. Aby uzyskać ramkę 100 px wokół zdjęcia 4000 × 3000, wpisz 5% i 6.6667%.

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

Testy uruchamiają prawdziwy ImageMagick, sprawdzają wymiary i kolor ramki, zachowanie pikseli TIFF 16-bit, JPEG, zerowe procenty, błędy i przywracanie pliku. Warstwa SDK Lightrooma jest symulowana. Lightroom Classic i Windows nie zostały uruchomione w tym środowisku.

Przed regularnym użyciem przetestuj w Lightroom Classic eksport jednego zdjęcia JPEG i TIFF oraz preset z własnym kolorem. Sprawdź wynikowe wymiary, profil ICC, metadane i pozycję znaku wodnego. To konieczny test integracji z rzeczywistym hostem, którego nie zastępują testy Linux.
